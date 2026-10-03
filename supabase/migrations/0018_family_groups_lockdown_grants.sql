-- Cierra los permisos de las funciones de 0017_family_groups.sql:
-- generate_family_invite_code y ensure_family_group son de uso interno
-- (el trigger las llama, nadie mas), nunca deben ser invocables como RPC.
-- get_entitlement_status y join_family_group SI son RPC publicas, pero
-- solo para usuarios autenticados (nunca anon, antes de iniciar sesion).

create or replace function public.generate_family_invite_code()
returns text
language sql
set search_path = public, pg_temp
as $$
  select upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
$$;

revoke execute on function public.generate_family_invite_code() from public;
revoke execute on function public.generate_family_invite_code() from anon;
revoke execute on function public.generate_family_invite_code() from authenticated;

revoke execute on function public.ensure_family_group() from public;
revoke execute on function public.ensure_family_group() from anon;
revoke execute on function public.ensure_family_group() from authenticated;

revoke execute on function public.get_entitlement_status() from public;
revoke execute on function public.get_entitlement_status() from anon;

revoke execute on function public.join_family_group(text) from public;
revoke execute on function public.join_family_group(text) from anon;
