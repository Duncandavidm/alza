-- Corrige los 3 hallazgos reales del security advisor de Supabase (RLS
-- ya estaba bien en todas las tablas, eso no salio en el advisor).

-- function_search_path_mutable: sin search_path fijo, una funcion
-- SECURITY DEFINER (o cualquiera, por si acaso) es vulnerable a que
-- alguien manipule el search_path del rol para hacerle "shadowing" a
-- una tabla/funcion con el mismo nombre en otro schema.
alter function public.set_updated_at() set search_path = public, pg_temp;
alter function public.increment_account_balance(p_account_id uuid, p_delta numeric)
  set search_path = public, pg_temp;

-- handle_new_user es SECURITY DEFINER y solo debe correr via el trigger
-- on_auth_user_created (que no depende de permisos EXECUTE directos).
-- Estaba expuesta como RPC publica llamable por anon/authenticated sin
-- necesitarlo — se le quita ese acceso directo.
revoke execute on function public.handle_new_user() from public;
revoke execute on function public.handle_new_user() from anon;
revoke execute on function public.handle_new_user() from authenticated;
