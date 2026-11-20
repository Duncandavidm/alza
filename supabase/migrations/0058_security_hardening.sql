-- Endurecimiento (revision de seguridad de Supabase, 13 nov 2026).
--
-- 1) Funciones internas que no deben llamarse desde la API.
revoke execute on function public.ai_spend_today() from public, anon, authenticated;
revoke execute on function public.points_ledger_hold_unbacked_cashback() from public, anon, authenticated;

-- 2) email_is_verified: una persona solo puede consultar su propio correo
--    (antes cualquiera con sesion podia preguntar por otro user_id). El
--    servidor (service role / funciones internas, sin auth.uid()) sigue
--    pudiendo consultar cualquiera.
create or replace function public.email_is_verified(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = public, auth, pg_temp as $$
  select (auth.uid() is null or auth.uid() = p_user_id)
     and (
       exists (select 1 from public.profiles p where p.id = p_user_id and p.email_verified_at is not null)
       or exists (select 1 from auth.identities i where i.user_id = p_user_id and i.provider = 'apple')
     );
$$;

-- 3) Bucket de logos: maximo 2 MB y solo imagenes.
update storage.buckets
set file_size_limit = 2097152,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
where id = 'business-logos';
