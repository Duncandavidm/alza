-- Programa de referidos.
--
-- Cada persona tiene un codigo de 6 caracteres. Quien se registra puede
-- escribir el codigo de quien lo invito durante sus primeros 7 dias.
-- Los premios son PUNTOS (no cashback, no cuesta dinero) y se entregan
-- solo cuando la persona invitada registra su primera factura confirmada,
-- para que no se puedan inventar cuentas solo por los puntos:
--   - invitado: 100 puntos
--   - quien invita: 200 puntos (maximo 10 referidos premiados cada 30 dias)

alter table public.points_ledger drop constraint points_ledger_source_check;
alter table public.points_ledger add constraint points_ledger_source_check
  check (source in ('factura', 'tarjeta', 'ahorro', 'habito', 'ajuste', 'canje', 'canje_puntos',
                    'marca', 'marca_puntos', 'bono', 'bono_puntos', 'referido_puntos'));

create or replace view public.points_balances with (security_invoker = true) as
select user_id,
  coalesce(sum(points) filter (where status = 'confirmado' and source in ('factura', 'tarjeta', 'ajuste', 'canje', 'marca', 'bono')), 0) as confirmed_points,
  coalesce(sum(points) filter (where status = 'pendiente' and source in ('factura', 'tarjeta', 'ajuste', 'canje', 'marca', 'bono')), 0) as pending_points,
  coalesce(sum(points) filter (where status = 'confirmado' and source in ('habito', 'canje_puntos', 'marca_puntos', 'bono_puntos', 'referido_puntos')), 0) as habit_points,
  coalesce(sum(points) filter (where status = 'confirmado' and source = 'habito' and points > 0), 0) as habit_points_earned
from public.points_ledger
group by user_id;

alter table public.profiles add column if not exists referral_code text unique;

create table public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references auth.users(id) on delete cascade,
  referee_id uuid not null unique references auth.users(id) on delete cascade,
  code text not null,
  status text not null default 'pendiente' check (status in ('pendiente', 'premiado', 'sin_premio')),
  created_at timestamptz not null default now(),
  rewarded_at timestamptz
);
create index referrals_referrer_idx on public.referrals (referrer_id, rewarded_at);
alter table public.referrals enable row level security;
create policy referrals_select_own on public.referrals
  for select to authenticated using (referrer_id = auth.uid() or referee_id = auth.uid());

-- Codigo propio (se crea la primera vez que se pide). Sin 0/O/1/I para
-- que no se confundan al dictarlo.
create or replace function public.my_referral_code()
returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_code text;
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i int;
begin
  if v_user is null then
    raise exception 'No autorizado' using errcode = '28000';
  end if;
  select referral_code into v_code from public.profiles where id = v_user;
  if v_code is not null then
    return v_code;
  end if;
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    begin
      insert into public.profiles (id, referral_code) values (v_user, v_code)
      on conflict (id) do update set referral_code = coalesce(public.profiles.referral_code, excluded.referral_code);
      exit;
    exception when unique_violation then
      -- codigo repetido: intenta otro
    end;
  end loop;
  select referral_code into v_code from public.profiles where id = v_user;
  return v_code;
end $$;
revoke execute on function public.my_referral_code() from public, anon;
grant execute on function public.my_referral_code() to authenticated;

-- La persona nueva escribe el codigo de quien la invito.
create or replace function public.apply_referral_code(p_code text)
returns text
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_referrer uuid;
  v_created timestamptz;
begin
  if v_user is null then
    raise exception 'No autorizado' using errcode = '28000';
  end if;
  if length(v_code) <> 6 then
    raise exception 'El código tiene 6 caracteres' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.referrals where referee_id = v_user) then
    raise exception 'Ya usaste un código de invitación' using errcode = 'P0001';
  end if;
  select created_at into v_created from auth.users where id = v_user;
  if v_created < now() - interval '7 days' then
    raise exception 'El código de invitación solo se puede usar en tus primeros 7 días' using errcode = 'P0001';
  end if;
  select id into v_referrer from public.profiles where referral_code = v_code;
  if v_referrer is null then
    raise exception 'Ese código no existe' using errcode = 'P0001';
  end if;
  if v_referrer = v_user then
    raise exception 'No puedes usar tu propio código' using errcode = 'P0001';
  end if;
  -- Evita cadenas cruzadas (A invita a B y B invita a A).
  if exists (select 1 from public.referrals where referrer_id = v_user and referee_id = v_referrer) then
    raise exception 'Ese código no se puede usar' using errcode = 'P0001';
  end if;

  insert into public.referrals (referrer_id, referee_id, code) values (v_referrer, v_user, v_code);
  -- Si ya tenia una factura confirmada, premia de una vez.
  perform public.reward_referral(v_user);
  return 'ok';
end $$;
revoke execute on function public.apply_referral_code(text) from public, anon;
grant execute on function public.apply_referral_code(text) to authenticated;

-- Entrega los puntos cuando la persona invitada tiene al menos una
-- factura confirmada. Idempotente (external_ref unico por referido).
create or replace function public.reward_referral(p_referee uuid)
returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r public.referrals%rowtype;
  v_recent int;
begin
  select * into r from public.referrals where referee_id = p_referee and status = 'pendiente' for update;
  if not found then
    return false;
  end if;
  if not exists (select 1 from public.dgi_receipts where user_id = p_referee and status = 'confirmada') then
    return false;
  end if;

  insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
  values (r.referee_id, 'referido_puntos', 'referido:' || r.id || ':invitado', 100, 'confirmado',
          jsonb_build_object('referral', r.id, 'role', 'invitado'))
  on conflict (source, external_ref) do nothing;

  select count(*) into v_recent from public.referrals
  where referrer_id = r.referrer_id and status = 'premiado' and rewarded_at > now() - interval '30 days';

  if v_recent < 10 then
    insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
    values (r.referrer_id, 'referido_puntos', 'referido:' || r.id || ':invita', 200, 'confirmado',
            jsonb_build_object('referral', r.id, 'role', 'invita'))
    on conflict (source, external_ref) do nothing;
    update public.referrals set status = 'premiado', rewarded_at = now() where id = r.id;
  else
    update public.referrals set status = 'sin_premio', rewarded_at = now() where id = r.id;
  end if;
  return true;
end $$;
revoke execute on function public.reward_referral(uuid) from public, anon, authenticated;

create or replace function public.dgi_receipts_reward_referral()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status = 'confirmada' and (tg_op = 'INSERT' or old.status is distinct from 'confirmada') then
    perform public.reward_referral(new.user_id);
  end if;
  return new;
end $$;
revoke execute on function public.dgi_receipts_reward_referral() from public, anon, authenticated;

create trigger dgi_receipts_reward_referral
  after insert or update of status on public.dgi_receipts
  for each row execute function public.dgi_receipts_reward_referral();

-- Resumen para la pantalla "Invita amigos".
create or replace function public.my_referral_summary()
returns table (code text, invited int, rewarded int, pending int, points_earned int, can_apply_code boolean, applied_code text)
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'No autorizado' using errcode = '28000';
  end if;
  return query
  select public.my_referral_code(),
    (select count(*)::int from public.referrals where referrer_id = v_user),
    (select count(*)::int from public.referrals where referrer_id = v_user and status = 'premiado'),
    (select count(*)::int from public.referrals where referrer_id = v_user and status = 'pendiente'),
    (select coalesce(sum(points), 0)::int from public.points_ledger where user_id = v_user and source = 'referido_puntos'),
    (not exists (select 1 from public.referrals where referee_id = v_user)
       and (select created_at from auth.users where id = v_user) > now() - interval '7 days'),
    (select rf.code from public.referrals rf where rf.referee_id = v_user);
end $$;
revoke execute on function public.my_referral_summary() from public, anon;
grant execute on function public.my_referral_summary() to authenticated;
