-- El país (y con él la moneda) se elige una sola vez, al registrarse.
-- Después de terminar el registro la cuenta no lo puede cambiar; solo el
-- servidor (panel / service role, sin auth.uid()) puede corregirlo.
create or replace function public.lock_profile_country()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null
     and old.onboarding_completed_at is not null
     and new.country is distinct from old.country then
    raise exception 'El país de la cuenta no se puede cambiar.' using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists profiles_lock_country on public.profiles;
create trigger profiles_lock_country
  before update of country on public.profiles
  for each row execute function public.lock_profile_country();
