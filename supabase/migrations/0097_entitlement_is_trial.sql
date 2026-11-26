-- 0097: get_entitlement_status devuelve is_trial.
-- La app (1.0.9) muestra en gris los descuentos, bonos y canjes mientras
-- la suscripcion esta en prueba gratis (el servidor ya los bloquea, 0096),
-- con el boton "Pasar a Pro ya". Las versiones viejas ignoran la columna.
drop function if exists public.get_entitlement_status();

create function public.get_entitlement_status()
returns table(status text, product_id text, expires_at timestamptz, via_family boolean, is_trial boolean)
language sql
stable
security definer
set search_path to 'public'
as $$
  select s.status, s.product_id, s.expires_at, false, coalesce(s.is_trial, false)
  from public.subscriptions s
  where s.user_id = auth.uid();
$$;

revoke all on function public.get_entitlement_status() from public, anon;
grant execute on function public.get_entitlement_status() to authenticated, service_role;
