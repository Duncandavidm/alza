# MonAvi Admin

Publicado en **https://monavi.maday.app** (Vercel, proyecto "monavi"):
se despliega solo con cada push a `claude/clever-planck-lf32rw`, con
Root Directory = `admin`. Landing publica de aliados:
https://monavi.maday.app/aliados

Panel interno minimo (Fase 4 del modulo de puntos): comercios aliados,
sus ofertas y productos canjeables, solicitudes de nuevos comercios,
canjes de puntos, estudio de mercado, subir reportes de comercio/banco,
ver resultados del cruce, y alertas (compras ambiguas, campañas con
presupuesto agotado).

## Paginas publicas (sin clave)

Viven en este mismo proyecto y estan en `PUBLIC_PATHS` de `proxy.ts`:

- `/aliados` — **landing para comercios** de Panama que quieren ser
  aliados de MonAvi (como funciona, beneficios y formulario). El
  formulario es una server action que inserta en
  `merchant_applications` (validacion en el servidor, limites de largo,
  campo honeypot oculto y tiempo minimo de llenado contra bots). URL
  para compartir: `https://<dominio-del-panel>/aliados` (el Resumen y
  Solicitudes la muestran con boton para copiar).
- `/privacy` y `/support` — exigidas por Apple para la app.

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

- **Comercios y ofertas** (`/merchants`, `/merchants/[id]`): crear,
  editar y pausar comercios aliados (`partner_merchants`) con su ficha
  (nombre, RUC, categoria, direccion, enlace de Google Maps para "Cómo
  llegar", logo); sus **productos canjeables** (`reward_items`: foto,
  nombre, costo en puntos, estado, orden) con vista previa de como se
  ven en la app; y sus ofertas de puntos (`partner_merchant_offers`) —
  porcentaje por dolar o puntos fijos, compra minima, presupuesto total.
  Logos y fotos se suben al bucket publico `rewards`
  (`logos/<merchantId>-<ts>.<ext>`, `products/<id>-<ts>.<ext>`; JPG,
  PNG o WebP, max 5 MB, validado en el servidor). Un producto con canjes
  no se puede borrar: se pausa.
- **Solicitudes** (`/applications`, `/applications/[id]`): lo que llega
  desde `/aliados`, con filtro y conteo por estado (nueva, contactada,
  aprobada, rechazada; la nav muestra cuantas hay nuevas). En el detalle
  se anotan notas internas, se cambia el estado y "Crear comercio
  aliado" crea el `partner_merchants` con los datos de la solicitud
  (pide el RUC si no vino), la marca `aprobada` con su `merchant_id` y
  lleva al comercio para subir logo y productos.
- **Canjes** (`/redemptions`): `reward_redemptions` mas recientes
  primero, con producto y comercio; busqueda por codigo y filtros por
  estado y comercio. En los `emitido` vigentes: "Marcar entregado" y
  "Cancelar y devolver puntos" (`release_redemption(..., 'cancelado')`).
  Los vencidos que siguen `emitido` se marcan "vencido (por liberar)":
  el cron nocturno los libera y devuelve los puntos.
- **Estudio de mercado** (`/insights?days=30|90|365&ruc=`): llama a la
  RPC `market_insights` (agregada y anonima, k=5) y muestra KPIs, formas
  de pago, genero, edades, categorias, rangos de ticket, productos y
  comercios top (marca aliados), canjes top, compras por hora y por dia,
  mapa de calor dia × hora, tendencia mensual y clientes que vuelven.
  "Reporte para un aliado" limita el estudio a los clientes de ese RUC.
  Cada seccion tiene "Descargar CSV" (`/insights/export?days=&ruc=&section=`,
  protegido por la sesion) y la pagina tiene una version para imprimir /
  guardar como PDF para compartir con el aliado.
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
- **Facturas DGI** (`/dgi-verification`): la verificacion corre todos
  los dias a las 8:00 a. m. (hora de Panama).
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
