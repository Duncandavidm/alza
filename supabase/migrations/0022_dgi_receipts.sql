-- "Facturas que suman": el usuario escanea el QR de una factura
-- electronica panameña (DGI), se registra el gasto de una vez, y cuando
-- la DGI confirma que la factura es real (no es instantaneo, ver
-- README_SECURITY.md / README.md) se acreditan puntos. Fase 1: solo el
-- escaneo + el gasto. La verificacion real contra la DGI (Fase 2) y los
-- puntos (Fase 3) llegan en migraciones aparte.

-- Comercios: mapea RUC -> nombre + categoria, para auto-rellenar la
-- categoria del gasto al escanear. Se llena a mano por David en el Table
-- Editor de Supabase (igual que las sugerencias de feedback hoy) — los
-- usuarios NO escriben aqui directo, para que nadie ensucie una tabla
-- compartida entre todos.
create table public.merchants (
  id uuid primary key default gen_random_uuid(),
  ruc text not null unique,
  name text not null,
  category text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.merchants enable row level security;

-- Cualquier usuario autenticado puede LEER (es catalogo compartido, no
-- hay nada sensible en nombre/categoria de un comercio). Sin policies de
-- insert/update/delete: solo la service role (Table Editor / futuras
-- Edge Functions) puede escribir.
create policy "merchants_select_authenticated" on public.merchants
  for select
  to authenticated
  using (true);

create trigger merchants_set_updated_at
  before update on public.merchants
  for each row execute procedure public.set_updated_at();

-- Facturas escaneadas. El CUFE es UNICO EN TODA LA BASE (no por usuario)
-- — asi el anti-duplicado real vive en Postgres: si otro usuario ya
-- registro ese CUFE, el insert truena con 23505 y el cliente lo muestra
-- como "ya fue registrada por alguien mas".
create table public.dgi_receipts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  transaction_id uuid references public.transactions (id) on delete set null,
  merchant_id uuid references public.merchants (id) on delete set null,

  cufe text not null unique,
  i_amb text not null default '1' check (i_amb = '1'),
  digest_value text,
  jwt text,

  -- Campos ya parseados del CUFE (ver MonAvi/Core/DGI/CufeParser.swift) —
  -- se guardan desnormalizados para no tener que re-parsear el CUFE cada
  -- vez que se lista o se le pregunta a la DGI.
  tipo_doc text not null,
  tipo_contribuyente text not null,
  ruc text not null,
  dv text not null,
  sucursal text not null,
  fecha_factura date not null,
  numero_documento text not null,
  punto_facturacion text not null,
  tipo_emision text not null,
  numero_seguridad text not null,
  digito_verificador text not null,

  status text not null default 'pendiente'
    check (status in ('pendiente', 'confirmada', 'rechazada', 'expirada')),

  -- Monto real que confirma la DGI (Fase 2) — hasta entonces el monto
  -- "de verdad" vive en transactions.amount, editable por el usuario.
  confirmed_amount numeric(14, 2),

  scanned_at timestamptz not null default now(),
  dgi_checked_at timestamptz,
  dgi_check_count int not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index dgi_receipts_user_id_idx on public.dgi_receipts (user_id);
create index dgi_receipts_status_idx on public.dgi_receipts (status);
create index dgi_receipts_merchant_id_idx on public.dgi_receipts (merchant_id);
create index dgi_receipts_transaction_id_idx on public.dgi_receipts (transaction_id);
-- La usa el job de Fase 2 para elegir que revisar: pendientes, mas
-- antiguas primero.
create index dgi_receipts_pending_check_idx on public.dgi_receipts (status, dgi_checked_at)
  where status = 'pendiente';

alter table public.dgi_receipts enable row level security;

create policy "dgi_receipts_select_own" on public.dgi_receipts
  for select
  using ((select auth.uid()) = user_id);

-- Solo se puede crear en estado 'pendiente' — el salto a
-- confirmada/rechazada/expirada lo hace unicamente el job de Fase 2 con
-- la service role key (sin policy de update para authenticated/anon,
-- ver abajo), para que un usuario no pueda marcar su propia factura como
-- "confirmada" y cobrar puntos sin que la DGI la haya validado de
-- verdad.
create policy "dgi_receipts_insert_own_pending" on public.dgi_receipts
  for insert
  with check ((select auth.uid()) = user_id and status = 'pendiente');

-- Dejar que el usuario borre un escaneo equivocado, pero solo mientras
-- siga pendiente (una vez confirmada o rechazada, queda como historial).
create policy "dgi_receipts_delete_own_pending" on public.dgi_receipts
  for delete
  using ((select auth.uid()) = user_id and status = 'pendiente');

create trigger dgi_receipts_set_updated_at
  before update on public.dgi_receipts
  for each row execute procedure public.set_updated_at();

-- Config simple del servidor para features que todavia no estan listas
-- para todos (ej. dgi_verification_enabled en Fase 2). Sin policies:
-- nadie de anon/authenticated la lee directo, solo la service role desde
-- las Edge Functions — asi se puede prender/apagar sin desplegar nada.
create table public.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;

create trigger app_config_set_updated_at
  before update on public.app_config
  for each row execute procedure public.set_updated_at();

insert into public.app_config (key, value) values
  ('dgi_verification_enabled', 'false'::jsonb);

-- Consentimiento de "Facturas que suman" (pantalla la primera vez: que
-- datos se guardan, que se verifica contra la DGI). nil = todavia no lo
-- ha visto.
alter table public.profiles
  add column dgi_scan_consent_at timestamptz;
