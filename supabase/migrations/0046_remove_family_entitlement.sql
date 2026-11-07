-- Se quito el plan Familia: el acceso Pro ya no se hereda de un grupo.
-- get_entitlement_status devuelve solo la suscripcion propia (via_family
-- queda siempre en false para no romper apps viejas que lean la columna).
create or replace function public.get_entitlement_status()
returns table (status text, product_id text, expires_at timestamptz, via_family boolean)
language sql
stable
security definer
set search_path = public
as $$
  select s.status, s.product_id, s.expires_at, false
  from public.subscriptions s
  where s.user_id = auth.uid();
$$;

-- Ya no se crean grupos al suscribirse.
drop trigger if exists subscriptions_ensure_family_group on public.subscriptions;
