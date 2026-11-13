-- Panel admin: limite de intentos de inicio de sesion y verificacion en
-- dos pasos (TOTP, app de autenticacion). Solo el servidor del panel
-- (service role) lee y escribe estas tablas: RLS activo y sin politicas.

create table public.admin_login_attempts (
  id bigint generated always as identity primary key,
  ip text not null,
  success boolean not null,
  created_at timestamptz not null default now()
);
create index admin_login_attempts_ip_idx on public.admin_login_attempts (ip, created_at desc);
alter table public.admin_login_attempts enable row level security;

-- Una sola fila: el panel tiene una cuenta de equipo.
create table public.admin_security (
  id smallint primary key default 1 check (id = 1),
  totp_secret text,
  totp_pending_secret text,
  totp_enabled boolean not null default false,
  totp_last_step bigint,
  updated_at timestamptz not null default now()
);
insert into public.admin_security (id) values (1) on conflict do nothing;
alter table public.admin_security enable row level security;

-- Limpieza: intentos de mas de 30 dias.
select cron.schedule('cleanup-admin-login-attempts', '41 4 * * *',
  $$delete from public.admin_login_attempts where created_at < now() - interval '30 days'$$);
