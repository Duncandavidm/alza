-- Comercios aliados con canje de puntos, solicitudes de comercios desde
-- una landing publica, detalle de productos de las facturas DGI, tokens
-- para notificaciones push, genero en el perfil, y estudio de mercado
-- agregado (anonimo) para el panel.

-- ---------------------------------------------------------------------------
-- 1) Ficha publica del comercio aliado (se llena en el panel)
-- ---------------------------------------------------------------------------
alter table public.partner_merchants
  add column logo_url text,
  add column maps_url text,
  add column category text,
  add column address text;

-- La app ya puede leer partner_merchants (policy
-- partner_merchants_select_authenticated de 0024): nada sensible, solo
-- nombre, logo y mapa.

-- ---------------------------------------------------------------------------
-- 2) Productos canjeables
-- ---------------------------------------------------------------------------
create table public.reward_items (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.partner_merchants (id) on delete cascade,
  name text not null,
  description text,
  photo_url text,
  points_cost integer not null check (points_cost > 0),
  status text not null default 'active' check (status in ('active', 'paused')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index reward_items_merchant_idx on public.reward_items (merchant_id);

alter table public.reward_items enable row level security;

create policy "reward_items_select_active" on public.reward_items
  for select to authenticated
  using (
    status = 'active'
    and exists (
      select 1 from public.partner_merchants m
      where m.id = merchant_id and m.status = 'active'
    )
  );

create trigger reward_items_set_updated_at
  before update on public.reward_items
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3) Canjes: el usuario genera un codigo que muestra en caja; el panel lo
--    marca como entregado. Los puntos se descuentan al generar el codigo
--    (fila negativa en el ledger) y se devuelven si se cancela o vence.
-- ---------------------------------------------------------------------------
alter table public.points_ledger drop constraint points_ledger_source_check;
alter table public.points_ledger add constraint points_ledger_source_check
  check (source in ('factura', 'tarjeta', 'ahorro', 'habito', 'ajuste', 'canje'));

create table public.reward_redemptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  reward_item_id uuid not null references public.reward_items (id) on delete restrict,
  merchant_id uuid not null references public.partner_merchants (id) on delete restrict,
  points_cost integer not null check (points_cost > 0),
  code text not null unique,
  status text not null default 'emitido'
    check (status in ('emitido', 'entregado', 'cancelado', 'vencido')),
  expires_at timestamptz not null default (now() + interval '7 days'),
  delivered_at timestamptz,
  created_at timestamptz not null default now()
);

create index reward_redemptions_user_idx on public.reward_redemptions (user_id);
create index reward_redemptions_item_idx on public.reward_redemptions (reward_item_id);
create index reward_redemptions_merchant_idx on public.reward_redemptions (merchant_id);

alter table public.reward_redemptions enable row level security;

create policy "reward_redemptions_select_own" on public.reward_redemptions
  for select using ((select auth.uid()) = user_id);

-- Unica forma de canjear: valida saldo y descuenta en una sola
-- transaccion (con lock por usuario para que dos toques seguidos no
-- gasten el mismo saldo dos veces).
create function public.redeem_reward(p_item_id uuid)
returns public.reward_redemptions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_item public.reward_items;
  v_merchant_status text;
  v_balance integer;
  v_code text;
  v_row public.reward_redemptions;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i integer;
begin
  if v_user is null then
    raise exception 'No autorizado' using errcode = '28000';
  end if;

  perform pg_advisory_xact_lock(hashtext('redeem:' || v_user::text));

  select * into v_item from public.reward_items where id = p_item_id;
  if v_item.id is null or v_item.status <> 'active' then
    raise exception 'Este producto ya no está disponible' using errcode = 'P0001';
  end if;
  select status into v_merchant_status from public.partner_merchants where id = v_item.merchant_id;
  if v_merchant_status is distinct from 'active' then
    raise exception 'Este comercio ya no está disponible' using errcode = 'P0001';
  end if;

  select coalesce(sum(points), 0) into v_balance
    from public.points_ledger
    where user_id = v_user and status = 'confirmado' and source <> 'habito';
  if v_balance < v_item.points_cost then
    raise exception 'No tienes puntos suficientes' using errcode = 'P0001';
  end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.reward_redemptions where code = v_code);
  end loop;

  insert into public.reward_redemptions (user_id, reward_item_id, merchant_id, points_cost, code)
  values (v_user, v_item.id, v_item.merchant_id, v_item.points_cost, v_code)
  returning * into v_row;

  insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
  values (
    v_user, 'canje', 'canje:' || v_row.id, -v_item.points_cost, 'confirmado',
    jsonb_build_object('rewardItemId', v_item.id, 'rewardName', v_item.name, 'code', v_code)
  );

  return v_row;
end;
$$;

revoke execute on function public.redeem_reward(uuid) from public, anon;
grant execute on function public.redeem_reward(uuid) to authenticated;

-- Cancelar (desde el panel) o vencer un canje devuelve los puntos.
create function public.release_redemption(p_redemption_id uuid, p_status text)
returns public.reward_redemptions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.reward_redemptions;
begin
  if p_status not in ('cancelado', 'vencido') then
    raise exception 'release_redemption: status invalido %', p_status;
  end if;

  update public.reward_redemptions
    set status = p_status
    where id = p_redemption_id and status = 'emitido'
    returning * into v_row;
  if v_row.id is null then
    select * into v_row from public.reward_redemptions where id = p_redemption_id;
    return v_row;
  end if;

  insert into public.points_ledger (user_id, source, external_ref, points, status, metadata)
  values (v_row.user_id, 'canje', 'canje:' || v_row.id || ':devolucion', v_row.points_cost, 'confirmado',
          jsonb_build_object('reason', p_status))
  on conflict (source, external_ref) do nothing;

  return v_row;
end;
$$;

revoke execute on function public.release_redemption(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) Solicitudes de comercios (landing publica del panel)
-- ---------------------------------------------------------------------------
create table public.merchant_applications (
  id uuid primary key default gen_random_uuid(),
  business_name text not null,
  ruc text,
  contact_name text not null,
  email text not null,
  phone text,
  category text,
  address text,
  maps_url text,
  instagram text,
  message text,
  status text not null default 'nueva'
    check (status in ('nueva', 'contactada', 'aprobada', 'rechazada')),
  notes text,
  merchant_id uuid references public.partner_merchants (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Sin policies: solo el panel (service role) lee y escribe.
alter table public.merchant_applications enable row level security;

create trigger merchant_applications_set_updated_at
  before update on public.merchant_applications
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 5) Detalle de facturas DGI (productos, comercio, hora real de compra)
-- ---------------------------------------------------------------------------
alter table public.dgi_receipts
  add column merchant_name text,
  add column authorized_at timestamptz;

create table public.dgi_receipt_items (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.dgi_receipts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  line_no integer not null,
  code text,
  description text not null,
  quantity numeric(14, 5),
  unit_price numeric(14, 5),
  total numeric(14, 5),
  unique (receipt_id, line_no)
);

create index dgi_receipt_items_user_idx on public.dgi_receipt_items (user_id);

alter table public.dgi_receipt_items enable row level security;

create policy "dgi_receipt_items_select_own" on public.dgi_receipt_items
  for select using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- 6) Tokens de notificaciones push (APNs)
-- ---------------------------------------------------------------------------
create table public.device_push_tokens (
  token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now()
);

create index device_push_tokens_user_idx on public.device_push_tokens (user_id);

alter table public.device_push_tokens enable row level security;

create policy "device_push_tokens_all_own" on public.device_push_tokens
  for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- 7) Genero (opcional) para el estudio de mercado
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column gender text
    check (gender in ('femenino', 'masculino', 'otro', 'prefiero_no_decir'));

-- ---------------------------------------------------------------------------
-- 8) Verificacion DGI una vez al dia, 8:00 a. m. de Panama (13:00 UTC)
-- ---------------------------------------------------------------------------
select cron.unschedule('verify-dgi-receipts');
select cron.schedule(
  'verify-dgi-receipts',
  '0 13 * * *',
  $$
  select net.http_post(
    url := 'https://jfhevxztsvnlsuwkwtmd.supabase.co/functions/v1/verify-dgi-receipt',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-admin-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'admin_job_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 300000
  );
  $$
);

-- Canjes no entregados en 7 dias: se vencen y se devuelven los puntos,
-- todos los dias a las 3:00 a. m. de Panama.
select cron.schedule(
  'expire-reward-redemptions',
  '0 8 * * *',
  $$
  select public.release_redemption(id, 'vencido')
    from public.reward_redemptions
    where status = 'emitido' and expires_at < now();
  $$
);

-- ---------------------------------------------------------------------------
-- 9) Logos de comercios y fotos de productos: bucket publico de lectura.
--    Solo el panel (service role) sube archivos.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('rewards', 'rewards', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
