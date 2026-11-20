-- Registro sin confirmar correo; el correo se verifica (codigo de 6
-- digitos) solo antes del PRIMER canje.
--
-- Con "Confirm email" apagado en Supabase, auth.users.email_confirmed_at se
-- llena solo al registrarse, asi que no sirve como prueba. La prueba es
-- profiles.email_verified_at, que solo marca mark_email_verified() cuando
-- la sesion viene de verificar un codigo enviado al correo (el JWT trae
-- amr = otp). Quien entra con Apple ya tiene el correo verificado por Apple.

alter table public.profiles add column email_verified_at timestamptz;

-- Las cuentas que ya existian (y confirmaron su correo con el flujo
-- anterior) quedan verificadas.
update public.profiles p set email_verified_at = u.email_confirmed_at
from auth.users u
where u.id = p.id and u.email_confirmed_at is not null and p.email_verified_at is null;

create or replace function public.email_is_verified(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = public, auth, pg_temp as $$
  select exists (select 1 from public.profiles p where p.id = p_user_id and p.email_verified_at is not null)
      or exists (select 1 from auth.identities i where i.user_id = p_user_id and i.provider = 'apple');
$$;
revoke execute on function public.email_is_verified(uuid) from public, anon;
grant execute on function public.email_is_verified(uuid) to authenticated;

-- La app la llama despues de verifyOTP. Solo marca si el JWT actual salio
-- de un codigo enviado al correo.
create or replace function public.mark_email_verified()
returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'No autorizado' using errcode = '28000';
  end if;
  if not jsonb_path_exists(coalesce(auth.jwt() -> 'amr', '[]'::jsonb), '$[*] ? (@.method == "otp" || @.method == "magiclink")') then
    raise exception 'Verifica el código que enviamos a tu correo' using errcode = 'P0001';
  end if;
  insert into public.profiles (id, email_verified_at) values (v_user, now())
  on conflict (id) do update set email_verified_at = coalesce(public.profiles.email_verified_at, now());
  return true;
end $$;
revoke execute on function public.mark_email_verified() from public, anon;
grant execute on function public.mark_email_verified() to authenticated;

-- redeem_reward exige correo verificado (mensaje que la app reconoce para
-- abrir la verificacion por codigo).
do $$
declare def text;
begin
  def := pg_get_functiondef('public.redeem_reward(uuid)'::regprocedure);
  if position('Verifica tu correo para canjear' in def) = 0 then
    def := replace(def,
      $o$  perform pg_advisory_xact_lock(hashtext('redeem:' || v_user::text));$o$,
      $n$  if not public.email_is_verified(v_user) then
    raise exception 'Verifica tu correo para canjear' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('redeem:' || v_user::text));$n$);
    if position('Verifica tu correo para canjear' in def) = 0 then
      raise exception 'redeem_reward: patron no encontrado';
    end if;
    execute def;
  end if;
end $$;
