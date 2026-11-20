-- Control de costo de IA: medicion, cuotas de uso justo y tope diario.
--
-- ai_usage: una fila por llamada a Claude (tokens y costo en USD).
-- Cuotas (app_config.ai_quotas): por funcion, por periodo (dia o mes,
-- hora de Panama). Tope global (app_config.ai_daily_budget_usd): si el
-- gasto de IA de hoy lo alcanza, las funciones de IA se pausan hasta
-- manana. Las Edge Functions llaman ai_guard() antes de Claude y
-- ai_record_usage() despues (service role).

create table public.ai_usage (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  function_name text not null,
  model text not null,
  input_tokens integer not null default 0,
  output_tokens integer not null default 0,
  cache_read_tokens integer not null default 0,
  cache_write_tokens integer not null default 0,
  cost_usd numeric(12, 6) not null default 0,
  -- true si fue un resultado guardado (no se llamo a Claude, no cuenta en cuota)
  cached boolean not null default false,
  created_at timestamptz not null default now()
);
create index ai_usage_created_idx on public.ai_usage (created_at);
create index ai_usage_user_fn_idx on public.ai_usage (user_id, function_name, created_at);
alter table public.ai_usage enable row level security;
-- Sin politicas: solo service role (Edge Functions y panel).

insert into public.app_config (key, value) values
  ('ai_quotas', '{
     "parse-voice-transaction": {"limit": 300, "period": "month"},
     "ask-finances": {"limit": 100, "period": "month"},
     "generate-insights": {"limit": 1, "period": "day"},
     "prioritize-payments": {"limit": 1, "period": "day"}
   }'::jsonb),
  ('ai_daily_budget_usd', '5'::jsonb)
on conflict (key) do nothing;

-- Inicio del periodo actual en hora de Panama.
create or replace function public.ai_period_start(p_period text)
returns timestamptz
language sql stable set search_path = public, pg_temp as $$
  select case when p_period = 'day'
    then date_trunc('day', now() at time zone 'America/Panama') at time zone 'America/Panama'
    else date_trunc('month', now() at time zone 'America/Panama') at time zone 'America/Panama'
  end;
$$;

create or replace function public.ai_period_end(p_period text)
returns timestamptz
language sql stable set search_path = public, pg_temp as $$
  select case when p_period = 'day'
    then public.ai_period_start('day') + interval '1 day'
    else public.ai_period_start('month') + interval '1 month'
  end;
$$;

create or replace function public.ai_spend_today()
returns numeric
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(sum(cost_usd), 0) from public.ai_usage where created_at >= public.ai_period_start('day');
$$;

-- Antes de llamar a Claude. Devuelve {allowed, reason, used, limit, resets_at}.
-- reason: 'quota' (se acabo la cuota de la persona) o 'budget' (tope global).
create or replace function public.ai_guard(p_user_id uuid, p_function text)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_quota jsonb := (select value -> p_function from public.app_config where key = 'ai_quotas');
  v_budget numeric := coalesce((select (value #>> '{}')::numeric from public.app_config where key = 'ai_daily_budget_usd'), 5);
  v_period text := coalesce(v_quota ->> 'period', 'month');
  v_limit int := (v_quota ->> 'limit')::int;
  v_used int;
begin
  select count(*) into v_used from public.ai_usage
  where user_id = p_user_id and function_name = p_function and not cached
    and created_at >= public.ai_period_start(v_period);

  if public.ai_spend_today() >= v_budget then
    return jsonb_build_object('allowed', false, 'reason', 'budget', 'used', v_used, 'limit', v_limit,
      'resets_at', public.ai_period_end('day'));
  end if;
  if v_limit is not null and v_used >= v_limit then
    return jsonb_build_object('allowed', false, 'reason', 'quota', 'used', v_used, 'limit', v_limit,
      'period', v_period, 'resets_at', public.ai_period_end(v_period));
  end if;
  return jsonb_build_object('allowed', true, 'used', v_used, 'limit', v_limit, 'period', v_period,
    'resets_at', public.ai_period_end(v_period));
end $$;
revoke execute on function public.ai_guard(uuid, text) from public, anon, authenticated;

create or replace function public.ai_record_usage(
  p_user_id uuid, p_function text, p_model text,
  p_input int, p_output int, p_cache_read int, p_cache_write int, p_cost numeric, p_cached boolean default false
) returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into public.ai_usage (user_id, function_name, model, input_tokens, output_tokens,
    cache_read_tokens, cache_write_tokens, cost_usd, cached)
  values (p_user_id, p_function, p_model, coalesce(p_input, 0), coalesce(p_output, 0),
    coalesce(p_cache_read, 0), coalesce(p_cache_write, 0), coalesce(p_cost, 0), coalesce(p_cached, false));
$$;
revoke execute on function public.ai_record_usage(uuid, text, text, int, int, int, int, numeric, boolean) from public, anon, authenticated;

-- Para la app: cuanto le queda a la persona de cada funcion.
create or replace function public.my_ai_quota()
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_quotas jsonb := (select value from public.app_config where key = 'ai_quotas');
  v_out jsonb := '{}'::jsonb;
  k text;
  v_period text;
  v_limit int;
  v_used int;
begin
  if v_user is null then
    raise exception 'No autorizado' using errcode = '28000';
  end if;
  for k in select jsonb_object_keys(v_quotas) loop
    v_period := coalesce(v_quotas -> k ->> 'period', 'month');
    v_limit := (v_quotas -> k ->> 'limit')::int;
    select count(*) into v_used from public.ai_usage
    where user_id = v_user and function_name = k and not cached
      and created_at >= public.ai_period_start(v_period);
    v_out := v_out || jsonb_build_object(k, jsonb_build_object(
      'used', v_used, 'limit', v_limit, 'remaining', greatest(v_limit - v_used, 0),
      'period', v_period, 'resets_at', public.ai_period_end(v_period)));
  end loop;
  return v_out;
end $$;
revoke execute on function public.my_ai_quota() from public, anon;
grant execute on function public.my_ai_quota() to authenticated;

-- Para el panel: gasto de hoy, del mes, y quienes mas gastan.
create or replace function public.admin_ai_costs()
returns jsonb
language sql stable security definer set search_path = public, auth, pg_temp as $$
  select jsonb_build_object(
    'today_usd', public.ai_spend_today(),
    'month_usd', (select coalesce(sum(cost_usd), 0) from public.ai_usage where created_at >= public.ai_period_start('month')),
    'budget_usd', coalesce((select (value #>> '{}')::numeric from public.app_config where key = 'ai_daily_budget_usd'), 5),
    'calls_today', (select count(*) from public.ai_usage where created_at >= public.ai_period_start('day') and not cached),
    'by_function', (select coalesce(jsonb_agg(f), '[]'::jsonb) from (
        select function_name, count(*) filter (where not cached) as calls, count(*) filter (where cached) as cached_hits,
               round(sum(cost_usd), 4) as cost_usd
        from public.ai_usage where created_at >= public.ai_period_start('month')
        group by function_name order by sum(cost_usd) desc) f),
    'top_users', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select u.email, a.user_id, count(*) filter (where not a.cached) as calls, round(sum(a.cost_usd), 4) as cost_usd
        from public.ai_usage a left join auth.users u on u.id = a.user_id
        where a.created_at >= public.ai_period_start('month')
        group by u.email, a.user_id order by sum(a.cost_usd) desc limit 15) t),
    'by_day', (select coalesce(jsonb_agg(d order by d.day), '[]'::jsonb) from (
        select (created_at at time zone 'America/Panama')::date as day, round(sum(cost_usd), 4) as cost_usd, count(*) as calls
        from public.ai_usage where created_at >= now() - interval '30 days'
        group by 1) d)
  );
$$;
revoke execute on function public.admin_ai_costs() from public, anon, authenticated;
