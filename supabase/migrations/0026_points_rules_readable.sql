-- La UI de habitos necesita mostrar "Te quedan X puntos este mes" — para
-- eso necesita leer el tope configurado (habito.monthly_cap_points).
-- Es seguro exponerlo: son numeros de configuracion, no dan ninguna
-- capacidad de escribir — el otorgamiento sigue siendo 100% server-side
-- via award_points().
create policy "points_rules_select_authenticated" on public.points_rules
  for select
  to authenticated
  using (true);
