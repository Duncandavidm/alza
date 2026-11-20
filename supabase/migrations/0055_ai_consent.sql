-- Permiso explicito para enviar datos a la IA de terceros (Claude, de
-- Anthropic). La app lo pide la primera vez que se usa una funcion con IA
-- y lo guarda en user_consents (proposito 'ia'). ai_guard lo revisa: sin
-- permiso vigente devuelve reason 'consent' y la Edge Function no llama a
-- Claude (prioritize-payments responde con razones genericas).

alter table public.user_consents drop constraint user_consents_purpose_check;
alter table public.user_consents add constraint user_consents_purpose_check
  check (purpose in ('estudio_mercado', 'programa_recompensas', 'ofertas', 'ia'));

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
  if not exists (
    select 1 from public.current_consents c
    where c.user_id = p_user_id and c.purpose = 'ia' and c.granted
  ) then
    return jsonb_build_object('allowed', false, 'reason', 'consent');
  end if;

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
