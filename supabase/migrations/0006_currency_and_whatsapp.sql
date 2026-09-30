-- Conversion automatica de moneda (inspirado en "Paga en otra moneda y MonAi
-- la convierte a la tuya al instante"): amount se sigue guardando en la
-- moneda de la cuenta (para que el balance/los reportes no tengan que
-- convertir nada), y aqui queda el registro de en que moneda/monto se
-- origino el movimiento, para mostrarlo si el usuario quiere verlo.
alter table public.transactions
  add column original_currency text,
  add column original_amount numeric(14, 2);

-- Vinculo de numero de WhatsApp a la cuenta (inspirado en "Escribe al bot de
-- MonAi por WhatsApp... y aparece en tu lista como transaccion"). El
-- usuario genera un codigo en la app y lo manda por WhatsApp al bot para
-- vincular su numero, sin necesitar un login completo desde WhatsApp.
alter table public.profiles
  add column whatsapp_number text unique;

create table public.whatsapp_link_codes (
  code text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  used_at timestamptz
);

alter table public.whatsapp_link_codes enable row level security;

create policy "whatsapp_link_codes_select_own" on public.whatsapp_link_codes
  for select using (auth.uid() = user_id);

create policy "whatsapp_link_codes_insert_own" on public.whatsapp_link_codes
  for insert with check (auth.uid() = user_id);
