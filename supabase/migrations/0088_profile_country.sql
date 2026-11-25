-- 1.0.6: pais y moneda de la persona. Panama = dolar (USD), Colombia =
-- peso colombiano (COP). La app formatea los montos con esa moneda y las
-- cuentas nuevas se crean en ella. Los montos no se convierten.
alter table public.profiles
  add column if not exists country text not null default 'PA';

alter table public.profiles drop constraint if exists profiles_country_check;
alter table public.profiles
  add constraint profiles_country_check check (country in ('PA', 'CO'));
