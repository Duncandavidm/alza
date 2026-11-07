# MonAvi Admin

Publicado en **https://monavi.maday.app** (Vercel, proyecto "monavi"):
se despliega solo con cada push a `claude/clever-planck-lf32rw`, con
Root Directory = `admin`. Landing publica de aliados:
https://monavi.maday.app/aliados · Canje en caja (comercios):
https://monavi.maday.app/canjear

**¿Olvidaste la clave del panel?** `ADMIN_PANEL_PASSWORD` esta guardada
como "Sensitive" en Vercel (no se puede ver). Cambiala en Settings >
Environment Variables > ⋯ > Edit y vuelve a publicar (Deployments >
Redeploy, o cualquier push a la rama de produccion).

Panel interno minimo (Fase 4 del modulo de cashback): comercios aliados,
sus ofertas y productos canjeables, PIN de canje en caja, solicitudes de
nuevos comercios, canjes, estudio de mercado, subir reportes de comercio/banco,
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
- `/canjear` — **canje en caja** para el cajero del comercio aliado
  (ver "Canje en caja con PIN" abajo).
- `/privacy` y `/support` — exigidas por Apple para la app.

No hay usuarios individuales — es una sola clave compartida
(`ADMIN_PANEL_PASSWORD`) para todo el equipo que administra esto.

## Cashback (convencion)

El ledger de puntos sigue guardando enteros, pero **1 punto = US$0.01**.
La regla actual (1 punto por dolar de factura) = 1% de cashback; el tope
diario de 300 = US$3.00. En TODA la UI se muestra dinero, nunca
"puntos/pts": `formatCashback(cents)` de `lib/format.ts` (350 -> "$3.50").

- `reward_items.points_cost` y `reward_redemptions.points_cost` son
  centavos. El formulario de producto pide "Valor en cashback (US$)"
  (ej. 3.50, > 0, max 2 decimales; `parseDollarsToCents`) y guarda 350.
- Ofertas (`partner_merchant_offers`): "percent" = puntos por dolar =
  % de cashback (se guarda igual); "fixed" y el presupuesto se escriben
  en US$ y se guardan en centavos.
- `/dgi-verification` sigue editando `points_rules` en puntos
  (`points_per_dollar` 1 = 1% de cashback; `daily_cap_points_per_user`
  300 = $3.00 al dia) y muestra su equivalente en dinero.
- `/insights`: `summary.points_issued` es "Cashback emitido" (valor/100).
- El comercio aliado regala el producto (MonAvi no le paga nada); el
  panel solo cuenta los canjes por comercio.

## Canje en caja con PIN

Migracion `0034_merchant_redeem_pin.sql`.

1. En `/merchants/[id]`, seccion "PIN de canje en caja", "Generar PIN
   nuevo" crea 6 digitos con `crypto.randomInt` (server action), llama a
   `set_merchant_redeem_pin` (guarda solo el hash bcrypt y
   `redeem_pin_set_at`) y muestra el PIN **una sola vez** con boton para
   copiarlo y un texto listo para enviar al comercio. Si ya habia PIN
   pide confirmacion: el anterior deja de funcionar. El PIN en claro no
   se guarda en ningun otro lado; si se pierde, se genera otro.
2. El cliente genera su codigo de 6 caracteres en la app; el QR codifica
   `https://monavi.maday.app/canjear?code=XXXXXX`, asi que el cajero lo
   escanea con la camara de cualquier celular y llega con el codigo
   escrito.
3. En `/canjear` (publica) el cajero escribe el PIN ("Recordar el PIN en
   este dispositivo" lo guarda en `localStorage` de ese navegador, con
   enlace para olvidarlo) y toca "Verificar": la server action llama a
   `merchant_redeem(p_confirm=false)` y muestra producto, foto, comercio,
   valor en cashback y vencimiento. "Confirmar entrega" llama con
   `p_confirm=true`: el canje queda `entregado` con
   `delivered_via='comercio'`. Los errores de la RPC se muestran tal cual.
4. Limite de intentos: la RPC corta tras 10 fallos por IP en 15 minutos.
   La IP (`x-forwarded-for`, primer valor, si no `x-real-ip`) nunca se
   guarda en claro: se envia `sha256(SESSION_SECRET + ":" + ip)`.

"Marcar entregado" en `/redemptions` deja `delivered_via='panel'`; la
tabla muestra "en caja" o "desde el panel".

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
  nombre, valor en cashback en US$, estado, orden) con vista previa de
  como se ven en la app; el PIN de canje en caja; y sus ofertas de
  cashback (`partner_merchant_offers`) — % de cashback o monto fijo,
  compra minima, presupuesto total.
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
  estado y comercio. En los `emitido` vigentes: "Marcar entregado"
  (`delivered_via='panel'`) y "Cancelar y devolver cashback"
  (`release_redemption(..., 'cancelado')`). Los entregados dicen si fue
  "en caja" (`/canjear`) o "desde el panel". Los vencidos que siguen
  `emitido` se marcan "vencido (por liberar)": el cron nocturno los
  libera y devuelve el cashback.
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
  los dias a las 8:00 a. m. (hora de Panama). Las reglas se editan en
  puntos con su equivalente en cashback.
- **Alertas** (`/alerts`): compras con 2+ tarjetas posibles (sin
  cashback, por diseño), reportes de banco sin inscripcion que los
  reclame, y campañas con presupuesto agotado.

## Por que no hay Supabase Auth aqui

El resto de la app (MonAvi) usa Supabase Auth con RLS por usuario. Este
panel es para un numero chico de operadores internos y necesita
saltarse RLS a proposito (ve filas que ningun usuario deberia ver,
como los reportes crudos del banco) — por eso usa la service role key
del servidor en vez de una sesion de Supabase, con su propia capa de
autenticacion minima (clave compartida + cookie firmada).
