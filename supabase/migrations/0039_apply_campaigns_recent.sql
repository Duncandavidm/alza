-- Aplica las campañas de marca a las facturas confirmadas en los ultimos
-- dias. Lo llama el job diario (award-habit-points, 8:15 a.m.), despues de
-- la verificacion DGI de las 8:00. Idempotente por (campaña, factura).
create function public.apply_brand_campaigns_recent(p_days integer default 3) returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_id uuid;
  v_total integer := 0;
begin
  if not exists (select 1 from public.brand_campaigns where status = 'active') then
    return 0;
  end if;
  for v_id in
    select id from public.dgi_receipts
    where status = 'confirmada' and dgi_checked_at >= now() - make_interval(days => greatest(p_days, 1))
  loop
    v_total := v_total + public.apply_brand_campaigns(v_id);
  end loop;
  return v_total;
end $$;
revoke execute on function public.apply_brand_campaigns_recent(integer) from public, anon, authenticated;
