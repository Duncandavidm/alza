-- 0073: el tope de amigos premiados por persona en 30 dias (antes fijo en
-- 10) ahora se edita desde el panel (app_config.referral_monthly_cap),
-- junto con los montos de cashback por invitar.

insert into public.app_config (key, value)
values ('referral_monthly_cap', '10'::jsonb)
on conflict (key) do nothing;

create or replace function public.reward_referral(p_referee uuid)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  r public.referrals%rowtype;
  v_recent int;
  v_referrer_cents int := coalesce((select (value #>> '{}')::int from public.app_config where key = 'referral_cashback_referrer_cents'), 100);
  v_referee_cents int := coalesce((select (value #>> '{}')::int from public.app_config where key = 'referral_cashback_referee_cents'), 50);
  v_cap int := coalesce((select (value #>> '{}')::int from public.app_config where key = 'referral_monthly_cap'), 10);
begin
  select * into r from public.referrals where referee_id = p_referee and status = 'pendiente' for update;
  if not found then
    return false;
  end if;
  if not exists (select 1 from public.dgi_receipts where user_id = p_referee and status = 'confirmada') then
    return false;
  end if;

  if v_referee_cents > 0 then
    insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
    values (r.referee_id, 'referido', 'referido:' || r.id || ':invitado', v_referee_cents, 'confirmado',
            jsonb_build_object('referral', r.id, 'role', 'invitado'))
    on conflict (source, external_ref) do nothing;
  end if;

  select count(*) into v_recent from public.referrals
  where referrer_id = r.referrer_id and status = 'premiado' and rewarded_at > now() - interval '30 days';

  if v_recent < v_cap and v_referrer_cents > 0 then
    insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
    values (r.referrer_id, 'referido', 'referido:' || r.id || ':invita', v_referrer_cents, 'confirmado',
            jsonb_build_object('referral', r.id, 'role', 'invita'))
    on conflict (source, external_ref) do nothing;
    update public.referrals set status = 'premiado', rewarded_at = now() where id = r.id;
  else
    update public.referrals set status = 'sin_premio', rewarded_at = now() where id = r.id;
  end if;
  return true;
end $function$;
