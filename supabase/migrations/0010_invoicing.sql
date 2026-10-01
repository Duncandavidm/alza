-- Facturacion: marca propia del negocio, catalogo con calculadora de
-- precio costo -> precio de venta, facturas/remisiones/cuentas por
-- cobrar con items, y recibos de pago (contraparte de las cuentas por
-- pagar, pero del lado de lo que el usuario le cobra a SUS clientes).

-- ---------------------------------------------------------------------------
-- business_settings: un renglon por usuario, la marca que se usa para
-- pintar facturas/remisiones/recibos (color, tipografia, logo).
-- ---------------------------------------------------------------------------
create table public.business_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  business_name text,
  logo_path text,
  brand_color text not null default '#00A585',
  brand_font text not null default 'default'
    check (brand_font in ('default', 'rounded', 'serif', 'monospaced')),
  tax_id text,
  address text,
  phone text,
  updated_at timestamptz not null default now()
);

alter table public.business_settings enable row level security;

create policy "business_settings_all_own" on public.business_settings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create trigger business_settings_set_updated_at
  before update on public.business_settings
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- products: catalogo con precio costo + margen -> precio de venta
-- (la calculadora "si es un comercio, sacar precio de venta").
-- ---------------------------------------------------------------------------
create table public.products (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  unit text,
  cost_price numeric(14, 2) not null default 0,
  margin_percent numeric(6, 2) not null default 0,
  sale_price numeric(14, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index products_user_id_idx on public.products (user_id);

alter table public.products enable row level security;

create policy "products_all_own" on public.products
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create trigger products_set_updated_at
  before update on public.products
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- invoices: facturas, remisiones o cuentas por cobrar que el usuario le
-- emite a SUS clientes (distinto de bills, que son cuentas que el
-- usuario mismo debe pagar).
-- ---------------------------------------------------------------------------
create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid references public.accounts (id) on delete set null,
  doc_type text not null check (doc_type in ('factura', 'remision', 'cuenta_por_cobrar')),
  number text,
  customer_name text not null,
  customer_contact text,
  issue_date date not null default current_date,
  delivered_date date,
  due_date date,
  status text not null default 'emitida'
    check (status in ('emitida', 'entregada', 'pagada', 'anulada')),
  subtotal numeric(14, 2) not null default 0,
  total numeric(14, 2) not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index invoices_user_id_idx on public.invoices (user_id);

alter table public.invoices enable row level security;

create policy "invoices_all_own" on public.invoices
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create trigger invoices_set_updated_at
  before update on public.invoices
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- invoice_items: lineas de cada factura/remision/cuenta por cobrar.
-- ---------------------------------------------------------------------------
create table public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  description text not null,
  quantity numeric(12, 2) not null default 1,
  unit_price numeric(14, 2) not null default 0,
  line_total numeric(14, 2) not null default 0,
  sort_order int not null default 0
);

create index invoice_items_invoice_id_idx on public.invoice_items (invoice_id);

alter table public.invoice_items enable row level security;

create policy "invoice_items_all_own" on public.invoice_items
  for all using (
    exists (select 1 from public.invoices i where i.id = invoice_id and i.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.invoices i where i.id = invoice_id and i.user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- payment_receipts: al marcar una factura como pagada, queda un recibo
-- (numero propio, monto, fecha) que se puede volver a compartir despues
-- sin tener que regenerar nada.
-- ---------------------------------------------------------------------------
create table public.payment_receipts (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  amount numeric(14, 2) not null,
  paid_at timestamptz not null default now(),
  receipt_number text not null,
  created_at timestamptz not null default now()
);

create index payment_receipts_invoice_id_idx on public.payment_receipts (invoice_id);

alter table public.payment_receipts enable row level security;

create policy "payment_receipts_all_own" on public.payment_receipts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- storage: bucket publico para logos de negocio (solo el dueño puede
-- subir/borrar el suyo; lectura publica porque el logo se incrusta en
-- facturas que se comparten fuera de la app).
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('business-logos', 'business-logos', true)
on conflict (id) do nothing;

create policy "business_logos_read_all" on storage.objects
  for select using (bucket_id = 'business-logos');

create policy "business_logos_write_own" on storage.objects
  for insert with check (
    bucket_id = 'business-logos' and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "business_logos_update_own" on storage.objects
  for update using (
    bucket_id = 'business-logos' and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "business_logos_delete_own" on storage.objects
  for delete using (
    bucket_id = 'business-logos' and (storage.foldername(name))[1] = auth.uid()::text
  );
