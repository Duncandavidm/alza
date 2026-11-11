-- Verificacion inmediata de facturas + reintento a las 24 horas.
--
-- 1) Al registrarse una factura (INSERT en dgi_receipts) se llama a
--    verify-dgi-receipt con {receipt_id}: consulta la DGI en ese momento y,
--    si la factura ya esta publicada, suma el cashback de una vez (con la
--    regla de ingresos de la migracion 0045) y manda el aviso push.
-- 2) Si la DGI aun no la tiene publicada, queda pendiente con
--    dgi_checked_at = ahora. El job pasa a correr cada hora y solo toma las
--    pendientes cuya ultima consulta fue hace 24 h o mas: la factura se
--    vuelve a consultar ~24 h despues del escaneo, y luego cada 24 h hasta
--    confirmarse o vencer (dgi_verification_expire_after_days).
-- La funcion respeta app_config.dgi_verification_enabled: si esta en
-- false, no consulta nada (ni inmediata ni periodica).

create or replace function public.dgi_receipts_verify_now()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status = 'pendiente' then
    perform net.http_post(
      url := 'https://jfhevxztsvnlsuwkwtmd.supabase.co/functions/v1/verify-dgi-receipt',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-admin-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'admin_job_secret')
      ),
      body := jsonb_build_object('receipt_id', new.id),
      timeout_milliseconds := 30000
    );
  end if;
  return new;
exception when others then
  -- Nunca impedir que se registre la factura: el job horario la verifica.
  return new;
end $$;
revoke execute on function public.dgi_receipts_verify_now() from public, anon, authenticated;

drop trigger if exists dgi_receipts_verify_now on public.dgi_receipts;
create trigger dgi_receipts_verify_now
  after insert on public.dgi_receipts
  for each row execute function public.dgi_receipts_verify_now();

-- Job: cada hora en vez de una vez al dia.
select cron.alter_job(
  (select jobid from cron.job where jobname = 'verify-dgi-receipts'),
  schedule := '7 * * * *'
);
