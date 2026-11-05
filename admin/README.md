# MonAvi Admin

Panel interno minimo (Fase 4 del modulo de puntos): comercios aliados y
sus ofertas, subir reportes de comercio/banco, ver resultados del
cruce, y alertas (compras ambiguas, campañas con presupuesto agotado).

No hay usuarios individuales — es una sola clave compartida
(`ADMIN_PANEL_PASSWORD`) para todo el equipo que administra esto.

## Variables de entorno

Ver `.env.example`. Las dos que este asistente no puede configurar por
su cuenta (requieren acceso directo al dashboard del usuario):

- `SUPABASE_SERVICE_ROLE_KEY` — Supabase Dashboard > Project Settings >
  API > `service_role` secret.
- `ADMIN_JOB_SECRET` — debe ser EXACTAMENTE el mismo valor que el
  `ADMIN_JOB_SECRET` configurado en las Edge Functions
  (`supabase secrets set ADMIN_JOB_SECRET=...` o desde el dashboard de
  Supabase, Edge Functions > Secrets).

`ADMIN_PANEL_PASSWORD` y `SESSION_SECRET` se pueden generar libremente
(no dependen de ningun tercero).

## Desarrollo local

```bash
cd admin
npm install
cp .env.example .env.local   # llenar los valores
npm run dev
```

## Que hace cada pantalla

- **Comercios y ofertas** (`/merchants`): crear/pausar comercios
  aliados (`partner_merchants`) y sus ofertas de puntos
  (`partner_merchant_offers`) — porcentaje por dolar o puntos fijos,
  compra minima, presupuesto total de la campaña.
- **Reportes de tarjeta** (`/card-reports`): subir un CSV de ventas con
  tarjeta de un comercio aliado (columnas: `provider_transaction_id,
  occurred_at, amount, card_last4, card_brand[, branch]`) e insertarlas
  en `card_transactions` con `provider='merchant_report'`. El boton
  "Procesar reportes pendientes" llama a la Edge Function
  `reconcile-card-transactions`, que cruza por ultimos4+marca contra
  las tarjetas vinculadas por los usuarios.
- **Bancos patrocinadores** (`/bank-partners`): crear/pausar bancos
  para "Ahorro verificado" (`bank_partners`).
- **Reportes de banco** (`/bank-reports`): subir un CSV del banco
  (columnas: `external_account_ref, period_month, avg_balance`) e
  insertarlas en `savings_bank_reports`. El boton "Procesar reportes
  pendientes" llama a `reconcile-savings-reports`.
- **Alertas** (`/alerts`): compras con 2+ tarjetas posibles (sin
  puntos, por diseño), reportes de banco sin inscripcion que los
  reclame, y campañas con presupuesto agotado.

## Por que no hay Supabase Auth aqui

El resto de la app (MonAvi) usa Supabase Auth con RLS por usuario. Este
panel es para un numero chico de operadores internos y necesita
saltarse RLS a proposito (ve filas que ningun usuario deberia ver,
como los reportes crudos del banco) — por eso usa la service role key
del servidor en vez de una sesion de Supabase, con su propia capa de
autenticacion minima (clave compartida + cookie firmada).
