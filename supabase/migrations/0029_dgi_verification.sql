-- "Facturas que suman" Fase 2 (verificacion real) + Fase 3 (puntos).
--
-- Confirmado en vivo contra dgi-fep.mef.gob.pa (ver reporte de la
-- sesion): el link directo por CUFE
-- (/Consultas/FacturasPorCUFE/<CUFE>) NO pide reCAPTCHA (a diferencia
-- del formulario de busqueda manual del sitio) y devuelve la factura
-- completa server-rendered en un <div id="facturaHTML">. Si el CUFE no
-- existe, ese div llega vacio — esa es la señal de "no confirmada"
-- (reconcile-savings-reports-style, ver Edge Function
-- verify-dgi-receipt).
--
-- Bonus: la factura trae "Forma de Pago" (ej. "Tarjeta Crédito: 84.25")
-- — con esto "tarjeta en comercios aliados" ya no necesita vincular
-- tarjeta ni depender de un reporte del comercio: si el RUC de la
-- factura es un comercio aliado con oferta activa y la DGI dice que se
-- pago con tarjeta, se acreditan puntos de tarjeta directo, verificado
-- por la DGI.

create extension if not exists pg_cron;
create extension if not exists pg_net;

alter table public.dgi_receipts
  add column payment_method text;

insert into public.points_rules (source, key, value) values
  ('factura', 'points_per_dollar', '1'::jsonb),
  ('factura', 'daily_cap_points_per_user', '300'::jsonb)
on conflict (source, key) do nothing;

-- Cuanto tiempo se sigue reintentando una factura antes de darla por
-- expirada si la DGI nunca la confirma (CUFE invalido, factura
-- fabricada, o que de verdad nunca se autorizo). No es necesariamente
-- fraude — por eso 'expirada', no 'rechazada' (ese estado queda
-- reservado para una revision manual futura).
insert into public.app_config (key, value) values
  ('dgi_verification_expire_after_days', '7'::jsonb)
on conflict (key) do nothing;

-- El cron llama a la Edge Function via pg_net con el mismo
-- x-admin-secret que ya exigen reconcile-card-transactions/
-- reconcile-savings-reports. El valor vive en Vault, nunca en esta
-- migracion ni en el codigo — hay que crearlo a mano UNA vez:
--
--   select vault.create_secret('<el mismo valor de ADMIN_JOB_SECRET>', 'admin_job_secret');
--
-- (Dashboard > Database > Vault, o el SQL de arriba desde el SQL
-- Editor.) Sin ese secret en Vault, el cron corre pero la funcion le
-- responde 401 — no truena, simplemente no hace nada hasta que se
-- cree.
select cron.schedule(
  'verify-dgi-receipts',
  '0 */6 * * *',
  $$
  select net.http_post(
    url := 'https://jfhevxztsvnlsuwkwtmd.supabase.co/functions/v1/verify-dgi-receipt',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-admin-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'admin_job_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
