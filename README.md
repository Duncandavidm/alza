# Alza (iOS, nativa)

Alza es una app de iPhone **100% nativa** (SwiftUI + StoreKit 2), sin
WKWebView y sin ninguna relacion con maday.app: backend propio (Supabase),
UI propia, suscripcion propia.

## Que hay en este repo

```
Alza/                       # codigo de la app
  App/                      # entry point, AppState (sesion + suscripcion)
  Core/                     # Supabase client, modelos, StoreKit, config
  Features/
    Auth/                   # Sign in with Apple + Sign in with Google (nativos)
    Paywall/                # suscripcion unica $29.99/mes, "Suscribirme"
    Dashboard/              # cuentas + movimientos (alta manual)
    Insights/               # insights de IA (Claude) sobre tus finanzas
    Settings/               # administrar suscripcion, restaurar, cerrar sesion
  Resources/                # Info.plist, Assets.xcassets (icono/color)
project.yml                 # spec de XcodeGen -> genera Alza.xcodeproj
supabase/
  migrations/0001_init.sql  # esquema ya aplicado al proyecto Supabase
  functions/
    generate-insights/      # Edge Function: llama a Claude, escribe ai_insights
    verify-apple-receipt/   # Edge Function: valida compras con Apple, escribe subscriptions
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

### 7. Insights de IA

```bash
supabase secrets set --project-ref jfhevxztsvnlsuwkwtmd \
  ANTHROPIC_API_KEY=<tu API key de Anthropic>
```

### 8. Icono y splash

`Alza/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` esta vacio
de imagenes — falta que pongas el icono de 1024x1024 ahi (y su referencia en
el Contents.json, o simplemente arrastralo en Xcode).

## Alcance de este MVP

- Auth: Sign in with Apple + Google (nativos, sin redirect web).
- Dashboard: cuentas y movimientos dados de alta a mano (no hay conexion
  bancaria tipo Plaid en este MVP).
- Insights: boton "Generar" que manda tus cuentas/movimientos a Claude y
  guarda 2-4 insights.
- Paywall: un solo boton "Suscribirme" a $29.99/mes, mas "Restaurar compras"
  y "Administrar suscripcion".

Conexion bancaria automatica, presupuestos, notificaciones locales, etc. no
estan en este primer corte — quedan para una siguiente iteracion.
