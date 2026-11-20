-- El panel llama a Edge Functions (send-push, etc.) con x-admin-secret.
-- En vez de depender de una copia del secreto en Vercel (que se puede
-- desincronizar), el panel lo lee del Vault con la service role. Solo la
-- service role puede ejecutarla (ya tiene acceso total a la base).
create or replace function public.admin_edge_secret()
returns text
language sql stable security definer set search_path = public, vault, pg_temp as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'admin_job_secret' limit 1;
$$;
revoke execute on function public.admin_edge_secret() from public, anon, authenticated;
grant execute on function public.admin_edge_secret() to service_role;
