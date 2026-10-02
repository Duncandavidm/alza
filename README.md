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

**Cancelaciones**: cuando un cliente cancela (desde Ajustes de iOS o el
sheet "Administrar suscripcion"), Apple NO corta el acceso de inmediato —
sigue activa hasta que termina el periodo ya pagado. Eso pasa automatico,
no hay nada que implementar ahi. Lo que SI se implemento es que el cliente
se entere: `SubscriptionStore.refreshRenewalInfo()` le pregunta a StoreKit
(local, sin pasar por el backend — no hay webhook de App Store Server
Notifications configurado) si la suscripcion activa se va a renovar sola
(`willAutoRenew`) y cuando termina el periodo pagado
(`currentPeriodEndDate`). Si `willAutoRenew == false`, aparece un banner en
"Hoy" ("Tu suscripcion no se va a renovar... Finaliza el [fecha]...") y el
mismo mensaje en Ajustes > Suscripcion, en vez del "Renueva el [fecha]"
normal. Se refresca al abrir la app, al entrar a Ajustes, y despues de
cualquier compra/restauracion.

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
- `AlzaMark.imageset/alza-mark.png` — el mark con fondo transparente
  (color), usado en el paywall.
- `AlzaMarkWhite.imageset/alza-mark-white.png` — version blanca del mark,
  usada sobre fondos oscuros (header de login).
- `AccentColor` = el verde/teal real de la marca (`#00A585`, sampleado
  directo del logo), aplicado automaticamente por iOS a casi todo
  (botones, toggles, graficas) sin tener que tocar cada pantalla.
- **`Alza/Core/Brand.swift`**: la paleta completa en un solo lugar
  (`AlzaBrand.primary/.primaryDark/.darkSurface/.onDarkSurface/.alert/
  .border/.headerGradient/.fontDesign`), para no repetir valores hex
  sueltos por toda la app. El header del login usaba `Color.black` como
  placeholder — ya no: ahora es `AlzaBrand.headerGradient` (degradado de
  teal de marca a un charcoal-teal oscuro, `#0E1614`, tomado del prompt
  original de la version web). La tipografia de marca usa el design
  "rounded" del sistema (SF Pro Rounded) — Inter/Manrope (lo que pedia
  el prompt original) requeriria embeber archivos .ttf reales en el
  proyecto, que no se pudo hacer con confianza sin poder compilar en
  este entorno; "rounded" da una energia moderna/geometrica similar sin
  esa dependencia. Aplicado por ahora en Auth y Paywall (las pantallas
  de marca mas fuertes); el resto de la app ya hereda el color via
  AccentColor pero sigue en la tipografia default del sistema.

Si en algun momento cambias el logo, reemplaza esos dos PNG (mismo
nombre de archivo) y ajusta los valores en `Brand.swift` si el color
cambio (y el `AccentColor` del asset catalog, que sigue siendo la
fuente para los controles nativos de iOS).

### 9. Seguridad

Repaso punto por punto de lo que se pidio reforzar:

1. **Token de sesion fuera de "local storage"**: en iOS no existe
   localStorage — su equivalente inseguro es UserDefaults/plist (sin
   cifrar, legible en un backup). `SupabaseManager` ahora pasa
   `KeychainAuthLocalStorage` (Core/KeychainAuthLocalStorage.swift,
   Security.framework puro, sin dependencias) al `SupabaseClient`, asi
   que el access/refresh token vive en el Keychain del dispositivo
   (cifrado por el Secure Enclave), nunca en UserDefaults. Con
   `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: no viaja por
   iCloud Keychain a otros dispositivos.
2. **Verificacion de admin del lado del servidor**: revisado — hoy la
   app NO tiene ninguna feature de admin ni ningun check de rol hecho en
   el cliente (`grep -rn "admin"` en todo `Alza/` no devuelve nada). No
   habia nada que corregir. Si en el futuro se agrega un panel de
   admin, la regla es: el cliente nunca decide quien es admin (nunca
   `if user.email == "..."` en Swift) — eso se hace con una columna
   `role`/`is_admin` en `profiles` verificada por una RLS policy o,
   mejor, por una Edge Function con la service role key, igual que ya
   hacen `verify-apple-receipt` y las funciones de IA.
3. **Verificacion en 2 pasos (2FA/TOTP)**: implementada completa —
   `Core/MFAService.swift` (envoltorio de `supabase.auth.mfa`),
   `Core/QRCodeGenerator.swift` (QR nativo con CoreImage, sin parsear el
   SVG que regresa Supabase), y en `Features/Security/`:
   `SecuritySettingsView` (Ajustes > Seguridad, activar/desactivar),
   `MFAEnrollView` (escanear QR + confirmar codigo) y
   `MFAChallengeView` (pantalla que `RootView` inserta despues de
   cualquier login si el usuario tiene 2FA activo y la sesion todavia
   no completo el segundo paso — no hay forma de saltarsela desde la
   app). Opcional, el usuario la activa el mismo desde Ajustes.
4. **Rate limiting contra fuerza bruta**: Supabase Auth YA trae esto
   activo por defecto en todos los proyectos — no es algo que se
   "prenda", es parte de GoTrue (limite por IP tipo token-bucket en
   login, refresh de token, challenge de MFA, etc.). Para verlo o
   ajustarlo mas estricto: **Dashboard > Authentication > Rate
   Limits**. Esto no se pudo tocar desde aqui porque requeriria un
   Management API token de tu cuenta de Supabase (no un secret de
   proyecto) — si quieres que lo ajuste, dame los valores que quieres y
   lo configuras tu ahi, o me das un token con alcance limitado.
5. **Reglas de contraseña**: lado del cliente ya reforzado —
   `Core/PasswordPolicy.swift` exige minimo 8 caracteres con letras y
   numeros (antes era solo 6 caracteres sin mas regla), con el mensaje
   de que falta exactamente. **Importante**: esto es solo UX — un
   cliente que le pega directo a la API de Supabase se salta cualquier
   validacion hecha en Swift. La regla real tiene que vivir tambien del
   lado del servidor: **Dashboard > Authentication > Policies >
   Password Requirements**, sube el minimo ahi tambien (y si quieres,
   activa el chequeo contra contraseñas filtradas, HaveIBeenPwned).
   Pendiente aparte: "Olvidaste tu contraseña" ya manda el correo de
   recuperacion, pero la app todavia no tiene la pantalla para
   completarlo (necesitaria Universal Links/Associated Domains con un
   dominio tuyo) — hoy el link de recuperacion no tiene donde
   aterrizar en la app.
6. **Acceso con Google**: ya estaba implementado (Sign in with Google
   nativo, sin WebView) desde antes en esta misma pantalla de login,
   con el mismo peso visual que Apple — no hizo falta cambiar nada ahi.
7. **Bucket de Storage (S3-compatible) para fotos**: ya se hacia asi
   para el logo del negocio (bucket `business-logos`, ver seccion de
   Facturacion arriba); se generalizo el patron en
   `Core/StorageUploadService.swift`, reutilizable para cualquier foto
   futura (bucket + path configurable). La regla de fondo, que es la
   que de verdad protege contra "cambiar de servidor rompe todo": la
   base de datos NUNCA guarda bytes de imagen ni una URL firmada que
   expira — solo guarda un PATH corto (ej.
   `business_settings.logo_path`), y la URL publica se arma al vuelo
   (`StorageUploadService.publicURL(bucket:path:)`). Si el dia de
   mañana cambias de proyecto Supabase o migras a un bucket
   self-hosted, solo hay que copiar los objetos del bucket — ninguna
   fila de ningun usuario en la base de datos relacional tiene que
   tocarse.

**Nada de esto se guardo hardcodeado en el repo** ("no guardes nada en
el backend de la app" — ningun secreto nuevo entro al codigo ni a
`project.yml`; las claves siguen viviendo solo como Supabase secrets o
en Apple/Google, igual que antes).

### 10. Hardening de las Edge Functions (CORS, validacion, rate limiting)

Repaso de la segunda ronda de seguridad pedida — ver el detalle completo
en `supabase/functions/README_SECURITY.md`, referenciado desde el
encabezado de cada funcion:

- **IDOR real corregido**: `verify-apple-receipt`, `generate-insights`,
  `ask-finances` y `prioritize-payments` tomaban el `userId` directo del
  body que mandaba el cliente y lo usaban con la service role key (que
  salta RLS) para leer/escribir esa tabla. Cualquier usuario autenticado
  podia mandar el `userId` de otra persona — el caso mas grave era
  `verify-apple-receipt`, donde se podia pisar la suscripcion de otro
  usuario. Corregido: el `userId` ahora SIEMPRE sale del JWT que el
  gateway de Supabase ya verifico (`getVerifiedUserId(req)`), nunca del
  body.
- **Rate limiting**: nuevo, `edge_function_rate_limits` +
  `check_and_increment_rate_limit` (migracion `0013_rate_limiting.sql`,
  contador atomico por usuario+funcion con ventana deslizante). Las 6
  Edge Functions de IA/terceros lo llaman antes de hacer trabajo real y
  regresan 429 si se pasa el limite (10-60 llamadas/10 min segun la
  funcion) — sin esto, cualquier usuario autenticado podia poner
  `generate-insights`/`ask-finances` en loop y disparar el costo de
  Anthropic.
- **CORS**: cada funcion responde el preflight, pero a proposito nunca
  manda `Access-Control-Allow-Origin` — ningun navegador puede llamarlas
  cross-origin. No afecta a la app nativa (CORS es cosa de navegadores).
  Documentado en el README de seguridad por que esto NO es lo mismo que
  "solo mi app puede llamar al backend" (eso requeriria App Attest, fuera
  de alcance).
- **Validacion de inputs del lado del servidor**: montos (numero finito,
  positivo, con tope), codigos de moneda (regex ISO 4217), texto libre
  (recortado y limitado en longitud) — antes de tocar la base o entrar a
  un prompt.
- **Mitigacion de prompt injection**: los prompts que arman
  generate-insights/ask-finances/prioritize-payments/parse-voice-transaction
  le dicen explicitamente a Claude que los datos del usuario son
  informacion a analizar, nunca instrucciones a seguir.
- **RLS**: ya estaba activo en TODAS las tablas desde que se crearon
  (verificado con el security advisor de Supabase — cero hallazgos de
  RLS). Lo que SI encontro el advisor y se corrigio (migracion
  `0012_security_hardening.sql`): dos funciones sin `search_path` fijo
  (`set_updated_at`, `increment_account_balance`) y `handle_new_user`
  (el trigger que crea el perfil al registrarse) expuesta como RPC
  publica llamable sin necesitarlo — se le revoco el EXECUTE directo a
  `anon`/`authenticated`.
- **Funcion huerfana neutralizada**: `whatsapp-webhook` (de la feature de
  WhatsApp que se descarto) seguia activa en el servidor con
  `verify_jwt: false` — publicamente invocable sin autenticacion, aunque
  su codigo ya no estaba en el repo. No hay forma de borrar la funcion
  por completo con las herramientas de este entorno, asi que se
  redeployo como un stub que regresa 410 + se activo verify_jwt. Si
  quieres quitarla del todo: Dashboard > Edge Functions >
  whatsapp-webhook > Delete.
- **Pendiente, requiere el Dashboard**: "Leaked Password Protection"
  (verificacion contra HaveIBeenPwned) sigue desactivada — es un toggle
  en Authentication > Policies que no se pudo prender desde aqui.
- **CSP**: no aplica — es un mecanismo que cumplen los navegadores al
  renderizar HTML/JS; estas funciones regresan JSON puro y Alza es una
  app nativa sin WebView, no hay nada que un CSP pudiera restringir.
- **Microinteracciones nativas**: se pidio "transiciones de pestañas
  fluidas, indicador de pestaña activa, microinteracciones, interfaz
  moderna, React + CSS + Framer Motion" — como Alza es 100% SwiftUI
  nativo (no hay React ni web de por medio), se tradujo la intencion al
  equivalente nativo: `Core/Microinteractions.swift` (`PressableButtonStyle`
  + `.pressable()`, el boton se encoge con resorte al presionarlo, igual
  que lograrias con Framer Motion en web) aplicado a los botones
  principales (+ flotante de "Hoy", "Suscribirme", "Iniciar sesion").
  **No se reemplazo el `TabView` del sistema por uno custom con
  indicador deslizante** — eso obligaria a mantener las 6 pestañas vivas
  en memoria todo el tiempo en vez de cargar solo la activa (TabView
  nativo es "lazy" por pestaña), un cambio de arquitectura y rendimiento
  real que no quise meter a ciegas sin poder probarlo visualmente. El
  indicador de pestaña activa que ya existe (icono relleno + texto en el
  color de marca) es el nativo de iOS.

## Alcance de este MVP

- **Facturacion con marca propia (Invoices/, Products/, Business/)**: el
  pestaña "Facturas" del tab bar deja crear facturas, remisiones o cuentas
  por cobrar para tus clientes, con items (manuales o desde tu catalogo de
  productos) y total automatico. Cada documento se pinta con la marca que
  configures en Ajustes > Mi negocio (logo subido a Supabase Storage,
  color y tipografia), asi que lo que ve el cliente es tu diseño, no uno
  generico. Flujo de estado: emitida -> entregada (boton "Marcar
  entregada") -> pagada; el vencimiento se muestra como cuenta regresiva
  ("Vence en 3 dias" / "Vencida hace 2 dias") igual que en Bills. Al
  marcar una factura como pagada se reusa la animacion de impresora +
  sello "PAGADO" (ReceiptStampView) y queda un recibo de pago guardado
  (payment_receipts) que se puede compartir — y volver a compartir despues
  — por el medio que el cliente prefiera (WhatsApp, correo, AirDrop...)
  via el share sheet nativo de iOS, renderizando el documento a PNG con
  ImageRenderer. Marcar como pagada tambien registra el ingreso real en la
  cuenta elegida, asi el "Hoy"/presupuestos/insights quedan consistentes.
- **Calculadora de precio costo -> precio de venta (Products/)**: Ajustes >
  Catalogo y precios. Para comercios: pones el precio costo y el margen
  que quieres ganar, Alza calcula el precio de venta en vivo (formula de
  margen sobre precio de venta, no sobre costo). Los productos guardados
  se pueden reusar como items al armar una factura.
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
- **Notificaciones locales** (`NotificationManager.swift`, Ajustes >
  Notificaciones): avisos programados en el propio dispositivo, sin
  servidor de por medio (no hace falta — todo esto ya lo sabe el telefono
  de antemano o lo acaba de calcular):
  - Cuenta por pagar y factura: un aviso X dias antes de vencer y otro el
    dia que vence — X es configurable en Ajustes (1-7 dias, default 3).
  - Recurrente (ej. luz el 20, tarjeta el 15): mismo aviso de X dias antes,
    usando `dayOfMonth` — se reprograma solo cada vez que se refresca la
    lista, calculando la proxima ocurrencia (evita el problema de un
    disparador repetitivo tratando de restar dias cerca del limite de un
    mes mas corto).
  - Al registrar un ingreso con consejo de pago disponible: notificacion
    inmediata con que pagar primero, ademas del pop-up que ya se mostraba
    en pantalla.
  Cada tipo de recordatorio se reprograma completo (se cancela lo
  pendiente y se vuelve a crear) cada vez que su lista cambia, con un
  identifier estable por registro, para que nunca queden duplicados ni
  avisos de algo ya pagado o borrado.
- **Estudio financiero inicial (Onboarding/)**: la primera vez que el usuario
  entra (despues de autenticarse, antes del paywall), un wizard de 14 pasos
  cortos — inspirado en el detalle del prompt original de la version
  web — le pregunta su nombre, panorama personal (edad, estado civil,
  dependientes, a que se dedica), su cuenta principal, si tiene un ingreso
  fijo (salario) y cuanto/que dia, si tiene ingresos variables (ventas,
  freelance), cuales cuentas fijas comunes paga (luz, alquiler, agua,
  telefono, internet) y cuanto, sus suscripciones (Netflix, gimnasio, etc.)
  y otras cuentas fijas mensuales (colegio, mesada, prestamos), sus deudas
  activas (tarjetas, prestamos — acreedor, saldo, interes, pago minimo, si
  esta en mora), sus ahorros/inversiones actuales, su tolerancia al riesgo,
  y sus metas de corto y largo plazo (texto libre). Al terminar, todo se
  guarda de una sola vez: crea la cuenta principal (y una de ahorro si
  aplica), un `recurring_transactions` por cada ingreso/gasto fijo
  marcado, una fila en `debts` por cada deuda, y actualiza el perfil
  (nombre, panorama personal, tolerancia al riesgo, metas,
  `onboarding_completed_at`). `AppState.onboardingStatus` (derivado de
  `onboarding_completed_at`) decide en `RootView` si mostrar el wizard antes
  del resto de la app; si el usuario sale a mitad de camino no queda a medias
  porque no hay escrituras parciales por paso. Este panorama completo es lo
  que le da a `prioritize-payments`, `generate-insights` y `ask-finances`
  contexto real desde el primer dia en vez de esperar a que el usuario cargue
  todo a mano con el tiempo.
- **Deudas (Debts/)**: Ajustes > Deudas. Tarjetas de credito, prestamos,
  sobregiros, con saldo, tasa de interes mensual, pago minimo y si estan en
  mora. `prioritize-payments` las toma en cuenta junto a cuentas por pagar y
  recurrentes vencidas — una deuda en mora o con interes alto puede subir de
  prioridad en el plan de pago. Marcar una deuda como pagada desde el
  consejo reduce su saldo (y la marca `paid_off` si llega a cero) ademas de
  registrar el gasto real.
- **Gastos por categoria (Insights > Gastos por categoria)**: dona con Swift
  Charts de en que se va el dinero (este mes o ultimos 3 meses), top 3
  categorias, y el cambio % de cada categoria contra el periodo anterior
  equivalente (ej. "Comida: +12% vs el mes pasado") para notar categorias
  que van creciendo antes de que se vuelvan un problema.
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
  con semaforo verde/amarillo/rojo segun cuanto te falta. Cada presupuesto
  tiene un color elegible a mano (`BudgetDetailSheet`).
- **Widget de pantalla de inicio** (target `AlzaWidget`, WidgetKit):
  tamaño pequeño y mediano, muestra el progreso de tus presupuestos.
  `BudgetsViewModel` escribe un snapshot al App Group compartido
  (`group.app.alza.shared`) cada vez que refresca/agrega/edita/borra un
  presupuesto y le avisa a WidgetKit que se redibuje — el widget mismo
  nunca toca Supabase ni el Keychain, solo lee ese snapshot.
- **Presupuesto restante al agregar un gasto**: si eliges una categoria
  con presupuesto (en el formulario detallado o, opcionalmente, en el
  ingreso rapido), se muestra en vivo cuanto te quedaria — restando lo ya
  gastado Y el monto que estas escribiendo — antes de guardar.
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
- **Anotar gasto por Atajos de Apple, con categoria automatica**
  (`AlzaShortcuts.swift` + `MerchantCategoryGuesser.swift`): expone un App
  Intent ("Anotar un gasto en Alza") que cualquier Atajo puede llamar,
  pensado para automatizarlo con el disparador real **"Transaccion"**
  (Atajos lo renombro **"Wallet"** en iOS 26) que Apple agrego en iOS 17
  para tarjetas/pases de Wallet — ese SI entrega monto y comercio como
  variables del disparador, confirmado contra como lo usan apps como
  MonAi. Alza no tiene ni puede tener acceso directo a Apple Pay/Wallet
  fuera de eso (no existe ese acceso para apps de terceros) — la
  automatizacion la arma el propio David en Atajos:
  1. Atajos > Automatizacion > Nueva automatizacion personal > Transaccion
     (o "Wallet" en iOS 26) > elige la(s) tarjeta(s) a vigilar.
  2. Agregar accion > buscar "Anotar un gasto en Alza" > en Monto y
     Comercio, usa las variables que entrega el disparador ("Shortcut
     Input" > Amount / Merchant) en vez de escribirlas a mano.
  3. Opcional: en "Cuenta" elige a cual cuenta de Alza (ej. "Tarjeta
     debito") apuntar esta automatizacion — si no eliges ninguna, cae en
     la primera cuenta que exista, igual que antes.
  4. Desactivar "Preguntar antes de ejecutar" si quieres que corra solo.

  El intent adivina la categoria por el nombre del comercio
  (restaurante, farmacia, gasolinera, etc. via `MerchantCategoryGuesser`,
  por palabras clave — instantaneo, sin IA ni red) y la guarda junto con
  el movimiento; si no reconoce el comercio, lo deja sin categoria en vez
  de forzar "Otro".
- **Metas de ahorro** (Ajustes > Metas de ahorro): ahorro a corto/largo
  plazo con nombre, emoji, monto objetivo y fecha limite ("Carro nuevo",
  $15,000, diciembre 2026). La cuota mensual necesaria para llegar a
  tiempo (`SavingsGoal.monthlyContributionNeeded`) NO se guarda en la
  base de datos — se recalcula siempre de monto restante y meses hasta
  la fecha limite (redondeando cualquier fraccion de mes hacia arriba),
  para que mover la fecha o registrar un aporte actualice el numero solo,
  sin desincronizarse. Cada meta puede vincularse a una cuenta de Alza;
  si la tiene, cada aporte ademas anota un movimiento real
  (transferencia, categoria Ahorro) para que ese dinero salga de ahi en
  el resto de la app, igual de simple que el resto de Alza (sin
  contabilidad de doble entrada).
- **Sugerencias** (Ajustes > Sugerencias): buzon simple donde el cliente
  escribe que le gustaria ver en Alza — se guarda en la tabla
  `feedback_suggestions` (RLS: cada cliente solo ve/borra las suyas) y
  queda ahi mismo como historial de lo ya enviado. No hay pantalla de
  admin dentro de la app: David revisa las sugerencias de todos los
  clientes directo en el dashboard de Supabase.

Conexion bancaria automatica no esta en este primer corte — queda para
una siguiente iteracion.

### Ideas de MonAi que se dejaron fuera por ahora

Tambien exploradas, pero no implementadas en esta pasada (para no meter
demasiado alcance nuevo de una vez):

- **Listas compartidas** (invitar a alguien mas a ver/anotar en el mismo
  negocio) — hoy el modelo de datos es un usuario = sus propios datos
  (RLS por `user_id`); compartir requeriria una tabla de invitaciones y
  cambiar las policies de RLS.
- **Bot de WhatsApp** — se exploro (Edge Function + vinculo de numero) pero
  se descarto; no esta en la app.

### Sobre "cuentas por cobrar" y el historial de clientes

El consejo de pago (`prioritize-payments`) cubre **cuentas por pagar**
(lo que tu negocio debe) y **deudas**. Emitir **cuentas por cobrar**
(facturas/remisiones a tus clientes) ya existe — ver Invoices/ arriba.
Lo que SI sigue sin construir es un historial de confiabilidad por
cliente (un puntaje de que tan a tiempo paga cada cliente segun su
historial) — hoy `customer_name`/`customer_contact` son campos de texto
libre en cada factura, no hay una tabla de clientes propia todavia. Es la
siguiente pieza natural si se quiere ese nivel de detalle.

### Ideas del prompt de la version web (Lovable) que se dejaron fuera por ahora

David compartio el prompt completo que uso para construir una version web
de Alza en Lovable (React/Supabase) y pidio aplicar mejoras de ahi a esta
app nativa. Se tomaron las partes de mayor valor y mas faciles de integrar
de verdad con lo que ya existe (perfil mas completo en el onboarding,
deudas, gastos por categoria). Lo que se dejo fuera por ahora, para no
disparar el alcance de una sola pasada:

- **Multi-idioma (ES/EN)**: el prompt pedia i18n completo con
  react-i18next; Alza es nativa SwiftUI, asi que el equivalente real seria
  un String Catalog (.xcstrings) con cada string de cada pantalla
  traducido — son decenas de archivos y requeriria revisar cada uno sin
  poder compilar en este entorno. Queda pendiente como su propia pasada.
- **Market & Opportunity Radar** (watchlist de acciones + feed de
  noticias via Alpha Vantage/News API): el prompt original lo deja como
  "Coming Soon" con datos de prueba hasta conectar llaves reales; no se
  construyo aqui porque Alza no tiene esas integraciones y no es el
  enfoque actual (asesoria personal/negocio, no trading).
- **Guia de ejecucion de inversiones** (checklist paso a paso por activo) —
  modulo nuevo grande, no conectado a lo que ya existe.
- **Conexion bancaria (Plaid)** — igual que en el prompt original, quedaria
  como integracion "Coming Soon"; la carga de movimientos sigue siendo
  manual/por voz/por Atajos.
- **Net worth con grafica de tendencia** — todavia no hay una grafica de
  patrimonio neto en el tiempo (las metas de ahorro con monto
  objetivo/actual y progreso visual si existen, ver Savings/ mas arriba).
- **Capital Leak Detector** (marcar suscripciones sin ingresos asociados
  como "fuga de capital") — Recurring/ ya muestra los gastos recurrentes,
  pero no tiene todavia la logica de "sin cliente activo hace 60 dias,
  sugerir cancelar" ni el flag `flagged_as_leak`.
