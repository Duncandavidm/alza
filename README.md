# Alza (iOS, nativa)

Alza es una app de iPhone **100% nativa** (SwiftUI + StoreKit 2), sin
WKWebView y sin ninguna relacion con maday.app: backend propio (Supabase),
UI propia, suscripcion propia.

**El diferenciador**: Alza no solo registra tus movimientos, te aconseja.
Cuando registras un ingreso, si tienes cuentas por pagar pendientes o
recurrentes vencidas, te dice — con IA, viendo tus datos reales — que
pagar primero y por que. Ver "Cuentas por pagar + consejo de pago" abajo.

## Que hay en este repo

```
Alza/                       # codigo de la app
  App/                      # entry point, AppState (sesion + suscripcion)
  Core/                     # Supabase client, modelos, StoreKit, config
  Features/
    Auth/                   # Sign in with Apple + Sign in with Google (nativos)
    Paywall/                # suscripcion unica $29.99/mes, "Suscribirme"
    Dashboard/              # "Hoy" (cuaderno del dia, voz), cuentas + busqueda
    Bills/                  # EL DIFERENCIADOR: cuentas por pagar + consejo de pago con IA
    Budgets/                # presupuestos por categoria, semanal o mensual
    Recurring/              # transacciones recurrentes (gestion en Ajustes)
    Insights/               # insights de IA (Claude) sobre tus finanzas
    Settings/               # suscripcion, modo avanzado, recurrentes,
                             # cuentas por pagar, exportar/importar CSV, logout
  Resources/                # Info.plist, Assets.xcassets (icono/color)
project.yml                 # spec de XcodeGen -> genera Alza.xcodeproj
supabase/
  migrations/               # 0001 esquema base, 0002 tipos de movimiento,
                             # 0003 RPC de balance, 0004 presupuestos,
                             # 0005 recurrentes + etiquetas, 0006 moneda
                             # (+ WhatsApp, revertido en 0007), 0008 cuentas
                             # por pagar
  functions/
    generate-insights/         # Edge Function: llama a Claude, escribe ai_insights
    verify-apple-receipt/      # Edge Function: valida compras con Apple, escribe subscriptions
    parse-voice-transaction/   # Edge Function: interpreta un movimiento dicho en voz alta
    ask-finances/               # Edge Function: responde preguntas en lenguaje natural
    exchange-rate/               # Edge Function: convierte moneda (frankfurter.app)
    prioritize-payments/         # Edge Function: EL DIFERENCIADOR, arma el consejo de pago
```

Este entorno (contenedor Linux, sin Xcode/Swift/CocoaPods/Deno) no puede
compilar ni correr nada de esto. Todo el codigo se escribio a mano sin poder
compilarlo — la primera vez que abras el proyecto en Xcode van a aparecer
errores que resolver.

## Backend (ya aprovisionado)

Proyecto Supabase nuevo, independiente del de maday:

- Project ref: `jfhevxztsvnlsuwkwtmd`
- URL: `https://jfhevxztsvnlsuwkwtmd.supabase.co`
- Publishable key: ya esta en `Alza/Core/Config.swift` (no es secreta)
- Esquema aplicado: `profiles`, `accounts`, `transactions`, `ai_insights`,
  `subscriptions`, todas con RLS por `user_id = auth.uid()`.
- Edge Functions desplegadas: `generate-insights`, `verify-apple-receipt`
  (ver notas de "sin probar" dentro de cada archivo — no hay Deno en este
  entorno para correrlas antes de desplegar).

## Lo que tienes que hacer a mano, en orden

### 1. Generar el proyecto Xcode

```bash
brew install xcodegen   # una sola vez
cd alza
xcodegen generate
open Alza.xcodeproj
```

### 2. Apple Developer

- Registrar un App ID nuevo. Bundle id sugerido: **`app.alza`** (o el que
  prefieras — actualiza `project.yml` y `Alza.entitlements` si cambias).
- Habilitar "Sign In with Apple" en ese App ID (el `project.yml` ya pide el
  entitlement, pero el capability tiene que existir en el portal).
- En Xcode: Signing & Capabilities > tu Team.

### 3. Google Sign-In

- Crear un proyecto en Google Cloud Console (o usar uno existente) con la
  API "Sign in with Google" habilitada.
- Crear un OAuth Client ID tipo **iOS**, con el bundle id `app.alza`.
- Poner ese Client ID en `Alza/Core/Config.swift` (`googleSignInClientId`).
- Poner el **REVERSED_CLIENT_ID** correspondiente en
  `Alza/Resources/Info.plist` (`CFBundleURLTypes`), reemplazando el TODO.

### 4. Supabase Auth providers

En el dashboard del proyecto `jfhevxztsvnlsuwkwtmd` (Authentication >
Providers):

- **Apple**: agregar `app.alza` a la lista de Client IDs autorizados (login
  nativo via `signInWithIdToken`, no hace falta Services ID ni redirect URL).
- **Google**: pegar el mismo Client ID de Google Cloud del paso 3.

### 5. App Store Connect

- Crear la ficha de app nueva bajo el bundle `app.alza`.
- Crear el producto de suscripcion: **$29.99/mes**, un solo tier. El Product
  ID tiene que coincidir exactamente con `Config.subscriptionProductId`
  (`app.alza.sub.pro` es el valor puesto ahora — cambialo ahi si usas otro).
- Categoria, privacy questionnaire, icono 1024x1024 (ponlo en
  `Alza/Resources/Assets.xcassets/AppIcon.appiconset/`), capturas.
- Banking/Tax: si ya los tienes configurados con maday en la misma cuenta de
  desarrollador, no hay que tocar nada (es a nivel cuenta, no por app).

### 6. Verificacion de compras (App Store Server API)

`verify-apple-receipt` necesita estos secrets en el proyecto Supabase:

```bash
supabase secrets set --project-ref jfhevxztsvnlsuwkwtmd \
  APPLE_BUNDLE_ID=app.alza \
  APPLE_ISSUER_ID=<Issuer ID de App Store Connect> \
  APPLE_KEY_ID=<Key ID de tu In-App Purchase Key> \
  APPLE_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
```

La "In-App Purchase Key" (.p8) se crea en App Store Connect > Users and
Access > Integrations > In-App Purchase.

**Antes de probar una compra real o sandbox**, revisa el archivo
`supabase/functions/verify-apple-receipt/index.ts` — se escribio sin poder
correr Deno ni pegarle a sandbox de Apple, asi que puede tener bugs en el
manejo de la respuesta de Apple. Pruebalo con
`supabase functions serve verify-apple-receipt` y una compra sandbox antes
de confiar en el.

### 7. Insights de IA (y registro por voz)

```bash
supabase secrets set --project-ref jfhevxztsvnlsuwkwtmd \
  ANTHROPIC_API_KEY=<tu API key de Anthropic>
```

El mismo secret lo usa tambien `parse-voice-transaction`, `ask-finances`, y
`prioritize-payments` (el diferenciador — ver "Cuentas por pagar" abajo) —
no hace falta configurarlo aparte para cada una.

No hace falta ninguna capability nueva en el Apple Developer portal para el
microfono/reconocimiento de voz — son solo los textos de permiso en
`Info.plist` (`NSMicrophoneUsageDescription`,
`NSSpeechRecognitionUsageDescription`), ya incluidos.

### 8. Icono y marca

Ya resuelto con el logo que diste (el mark de la "a" con flecha):

- `AppIcon.appiconset/AppIcon-1024.png` — icono de App Store, fondo blanco.
- `AlzaMark.imageset/alza-mark.png` — el mark con fondo transparente, usado
  dentro de la app (header de login, paywall).
- `AccentColor` actualizado al verde/teal real de la marca (`#00A585`).

Si en algun momento cambias el logo, solo reemplaza esos dos PNG (mismo
nombre de archivo) y ajusta el `AccentColor` si el color cambio.

## Alcance de este MVP

- **Cuentas por pagar + consejo de pago con IA (Bills/, el diferenciador)**:
  das de alta facturas/recibos pendientes con fecha de vencimiento
  (Ajustes > Cuentas por pagar; tambien visible como franja arriba de
  "Hoy"). Cada vez que registras un **ingreso** — desde el ingreso
  ultra-rapido o el formulario detallado — si hay cuentas por pagar
  pendientes o recurrentes vencidas, `prioritize-payments` (Claude) arma un
  plan priorizado: que pagar primero, por que (vencimiento, riesgo de
  corte en servicios, prioridad que le pusiste), y si el ingreso alcanza
  para todo. Aparece como un pop-up justo despues de guardar, con un boton
  "Pagar" por cada item que registra el gasto real y lo marca resuelto sin
  salir de la pantalla.
- Auth: Sign in with Apple + Google (nativos, sin redirect web).
- **"Hoy" (Mi cuaderno del dia)**: pantalla principal — feed cronologico de
  todo lo que paso hoy (como una libreta, no una tabla), boton flotante "+"
  para el ingreso ultra-rapido (solo ¿cuanto? + ¿que fue?, tipo de
  movimiento opcional con un toque), total del dia siempre visible arriba
  ("Hoy llevas: +$X ingresos — $Y gastos = $Z en tu bolsillo"), y "Cerrar el
  dia" con un resumen de si fue buen dia / dia normal / dia flojo
  (comparado contra el promedio de los ultimos 7 dias).
- **Anotar por voz** (inspirado en MonAi): en el ingreso ultra-rapido, boton
  de microfono — dictas el movimiento ("pague veinte dolares de gasolina"),
  Speech framework lo transcribe (on-device cuando el dispositivo lo
  soporta) y `parse-voice-transaction` (Claude) lo convierte en monto,
  descripcion, tipo de movimiento y categoria. El usuario revisa y confirma
  antes de guardar, no se guarda solo.
- Tipos de movimiento: 💰 Ingreso, 💸 Gasto, 🏭 Pago a proveedor,
  📈 Inversion, 💳 Transferencia — columna `movement_type` en
  `transactions` (migracion `0002_movement_types.sql`).
- "Cuentas": alta manual de cuentas y formulario detallado de movimientos
  (con categoria opcional), para cuando el ingreso rapido no basta.
- **Presupuestos** (inspirado en MonAi): limite semanal o mensual por
  categoria, con barra de progreso — visible tanto en su propia pestaña
  como en una franja arriba de "Hoy" ("justo en la pantalla principal"),
  con semaforo verde/amarillo/rojo segun cuanto te falta.
- Insights: boton "Generar" que manda tus cuentas/movimientos a Claude y
  guarda 2-4 insights.
- **Informes con IA** (inspirado en MonAi 1.10): en Insights, un campo para
  preguntar algo puntual en lenguaje normal ("¿cuanto gaste en comida este
  mes?") — `ask-finances` responde con los numeros reales, sin guardar nada.
- **Conversion automatica de moneda** (inspirado en MonAi 1.10): en el
  formulario detallado (modo avanzado), eliges en que moneda pagaste;
  `exchange-rate` (frankfurter.app, tasas del BCE) convierte el monto a la
  moneda de la cuenta al guardar, y deja el monto original visible en el
  movimiento.
- **Exportar / Importar CSV** (inspirado en MonAi 1.10, Ajustes > Exportar
  / Importar): exporta todos tus movimientos y recurrentes a un CSV
  (compartible por cualquier medio), o importa uno de vuelta a una cuenta
  que elijas.
- Paywall: un solo boton "Suscribirme" a $29.99/mes, mas "Restaurar compras"
  y "Administrar suscripcion".
- Cerrar sesion (en Ajustes y en el Paywall) muestra un spinner y se
  deshabilita mientras corre, para que quede claro que esta funcionando.
- **Recurrentes** (Ajustes > Recurrentes): pagos/ingresos fijos mensuales
  (renta, Netflix). El dia que le toca a una, "Hoy" muestra un recordatorio
  ("¿Pagaste Netflix hoy? [Si, lo pague] [Recordarme despues]") que registra
  el movimiento real al confirmar.
- **Etiquetas + busqueda**: en el formulario detallado (modo avanzado),
  etiquetas tipo `#cine #viaje`; en "Cuentas", una barra de busqueda que
  busca por texto o, si escribes `#algo`, por esa etiqueta.
- **Modo Simple / Avanzado** (Ajustes): en Simple (default), el formulario
  detallado de movimiento solo pide cuenta, tipo, monto y descripcion. En
  Avanzado se agregan categoria y etiquetas.
- **Anotar gasto por Atajos de Apple** (`AlzaShortcuts.swift`): expone un
  App Intent ("Anotar un gasto en Alza") que cualquier Atajo puede llamar,
  pensado para automatizarlo con el disparador "Transaccion de Apple Pay"
  de la app Atajos. Alza no tiene ni puede tener acceso directo a Apple
  Pay/Wallet (eso no existe para apps de terceros) — la automatizacion la
  arma el propio David en Atajos:
  1. Atajos > Automatizacion > Nueva automatizacion personal > Transaccion
     de Apple Pay.
  2. Agregar accion > buscar "Anotar un gasto en Alza" > llenar monto y
     descripcion (o mapearlos desde lo que entregue el disparador).
  3. Desactivar "Preguntar antes de ejecutar" si quieres que corra solo.

Conexion bancaria automatica y notificaciones locales no estan en este
primer corte — quedan para una siguiente iteracion.

### Ideas de MonAi que se dejaron fuera por ahora

Tambien exploradas, pero no implementadas en esta pasada (para no meter
demasiado alcance nuevo de una vez):

- **Widgets de pantalla de inicio** con el progreso de presupuestos — pide
  un target de Widget Extension nuevo, App Group compartido, y no se pudo
  armar/probar con confianza sin Xcode en este entorno.
- **Listas compartidas** (invitar a alguien mas a ver/anotar en el mismo
  negocio) — hoy el modelo de datos es un usuario = sus propios datos
  (RLS por `user_id`); compartir requeriria una tabla de invitaciones y
  cambiar las policies de RLS.
- **Bot de WhatsApp** — se exploro (Edge Function + vinculo de numero) pero
  se descarto; no esta en la app.

### Sobre "cuentas por cobrar" y el historial de clientes

El consejo de pago de arriba solo cubre **cuentas por pagar** (lo que tu
negocio debe). Lo de "cuenta por cobrar segun el historial del cliente"
que se pidio junto con esto — es decir, llevar clientes, las facturas que
les emitiste, y un puntaje de que tan confiables son para pagar a tiempo —
es un modulo bastante mas grande (tabla de clientes, facturas emitidas por
cliente, historial de pagos, logica de puntaje) que no se armo en esta
pasada para no mezclar dos features grandes a la vez. Si se quiere, es la
siguiente pieza natural a construir sobre esta misma base.
