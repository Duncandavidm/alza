-- 0098: idioma de la app (1.1.0). La app lo guarda al entrar y al cambiarlo
-- en Ajustes; la IA, los avisos del servidor y los correos lo usan.
alter table public.profiles
  add column if not exists language text not null default 'es'
  check (language in ('es', 'en'));
