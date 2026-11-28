# Prompts para Claude en Chrome · MonAvi 1.1.0

Úsalos uno por uno, con la sesión ya iniciada en cada sitio. Ninguno escribe
contraseñas ni códigos, ninguno manda la app a revisión ni cambia precios.

---

## 1 · App Store Connect: privacidad de la app

```
Estás en App Store Connect (appstoreconnect.apple.com) con mi sesión iniciada. Ve a Apps → MonAvi → en el menú de la izquierda, "Privacidad de la app" (App Privacy).

Quiero actualizar las etiquetas de privacidad SIN tocar nada más. Toca "Editar" en los tipos de datos recopilados y agrega o confirma estos dos:

1. Identificadores → "ID del dispositivo" (Device ID):
   - Uso: solo "Funcionalidad de la app" (App Functionality).
   - ¿Vinculado a la identidad del usuario? Sí.
   - ¿Se usa para rastrear (tracking)? No.

2. Fotos o videos (Photos or Videos):
   - Uso: solo "Funcionalidad de la app".
   - ¿Vinculado a la identidad del usuario? Sí.
   - ¿Se usa para rastrear? No.

No quites ni cambies los otros tipos de datos que ya están marcados. Si "ID del dispositivo" ya estaba, solo confirma que tenga exactamente esas respuestas. Al final toca "Guardar" y luego "Publicar" en la sección de privacidad (esto no manda la app a revisión).

Reglas: no escribas contraseñas ni códigos; si te pide iniciar sesión o un código de verificación, detente y avísame. No mandes nada a revisión ni cambies precios. Al terminar, dime qué quedó marcado en cada tipo de dato.
```

---

## 2 · App Store Connect: ficha en inglés y novedades de la 1.1.0

```
Estás en App Store Connect con mi sesión iniciada. Ve a Apps → MonAvi.

Paso A. En la lista de versiones de iOS, revisa si existe la versión 1.1.0. Si no existe, toca "+" junto a "App para iOS" y crea la versión 1.1.0. No selecciones build ni la mandes a revisión.

Paso B. Arriba a la derecha está el menú de idioma (dice "Español" o "Spanish (Mexico)" o similar). Ábrelo y toca "Agregar idioma" → "English (U.S.)". Si ya existe, solo cámbiate a English (U.S.).

Paso C. Con English (U.S.) elegido, en "Información de la app" (App Information, menú izquierdo) llena:
- Name: MonAvi: Budget & Cashback
- Subtitle: Track spending, earn cashback
- Privacy Policy URL: https://monavi.maday.app/en/privacy
Guarda.

Paso D. Vuelve a la versión 1.1.0, con English (U.S.) elegido, y llena:
- Promotional Text: Log a purchase in seconds by voice, scan your receipt and get cashback at partner stores. Now in English.
- Keywords: expense,tracker,money,budgeting,savings,receipt,invoice,panama,rewards,bills,voice,ai,planner,wallet
- Support URL: https://monavi.maday.app/support
- Marketing URL: https://monavi.maday.app
- What's New in This Version:
Thanks for using MonAvi!

• MonAvi now speaks English: choose your language when you start or anytime in Settings.
• Verify your income to count your full earnings toward cashback.
• A faster sign-up, without the extra steps at the end.
• Stronger protections to keep cashback fair for everyone.
• Improvements and fixes.

- Description (copia exactamente, respetando los saltos de línea):
MonAvi helps you know where your money goes, spend with intention, and get something back every time you shop.

LOG IN SECONDS
• Say it out loud: "25 dollars at the supermarket" and MonAvi fills in the amount, category and account.
• Today shows your day like a notebook: what came in, what went out and what's left.
• Detect payments from your bank's notifications and save them with one tap.

CASHBACK AND DISCOUNTS
• Scan the QR code on your receipt and earn cashback at partner stores.
• Unlock discounts and bonuses from local businesses as you build good money habits.
• Redeem your cashback right in the app.

A BUDGET THAT TAKES CARE OF YOU
• Weekly or monthly budgets by category.
• Alerts when a balance goes negative or when you're spending too fast in a category.
• Bills to pay and recurring payments, so nothing catches you off guard.

ADVICE, NOT JUST CHARTS
• Ask about your finances in plain words: "How much did I spend on food this month?"
• When you get paid, MonAvi suggests what to pay first and why.
• Personalized insights and the MonAvi Method, a 7-step plan to get your finances in order.

SAVE AND GROW
• Savings goals with progress you can see.
• Levels and challenges that reward consistency.
• Credit cards with their cut-off and payment dates.

MADE FOR YOU
• Spanish or English, your choice.
• Home Screen widgets, Face ID lock and CSV export.
• Share your plan with your family.

MONAVI PRO
Start with a 7-day free trial. MonAvi Pro is an auto-renewable subscription, available monthly or yearly. Payment is charged to your Apple ID account when you confirm the purchase after the trial ends. It renews automatically unless you turn it off at least 24 hours before the end of the current period. You can manage or cancel it anytime in your App Store account settings. Cashback, discounts and redemptions unlock once the trial ends and your subscription is active.

Terms of Use: https://monavi.maday.app/en/terms
Privacy Policy: https://monavi.maday.app/en/privacy

Guarda.

Paso E. Cámbiate al idioma español y, en la misma versión 1.1.0, pon en "Novedades de esta versión" (si está vacío o tiene el texto de la versión anterior):
¡Gracias por usar MonAvi!

• MonAvi ahora está en inglés: elige tu idioma al empezar o cuando quieras en Ajustes.
• Verifica tus ingresos para que cuente todo lo que ganas en tu cashback.
• Un registro más rápido, sin pasos extra al final.
• Más protecciones para que el cashback sea justo para todos.
• Mejoras y correcciones.

No cambies la descripción ni las capturas en español. Guarda.

Reglas: no subas capturas, no elijas build, no toques precios ni disponibilidad, no mandes nada a revisión. No escribas contraseñas ni códigos; si te los pide, detente y avísame. Si un campo pasa del límite de caracteres, avísame en vez de recortarlo. Al terminar, dime qué quedó guardado en cada idioma y si App Store Connect marca algún campo como pendiente.
```

---

## 3 · Apple Developer: clave de DeviceCheck

```
Estás en developer.apple.com con mi sesión iniciada. Ve a Account → Certificates, Identifiers & Profiles → Keys.

Crea una clave nueva:
- Toca "+".
- Key Name: MonAvi DeviceCheck
- Marca solo "DeviceCheck".
- Continue → Register.

En la pantalla final, NO toques "Download" tú: dime el "Key ID" que aparece (son 10 caracteres) y avísame que la clave está lista para que yo mismo la descargue. No abras, leas ni copies el contenido del archivo .p8.

Reglas: no revoques ni edites otras claves. No escribas contraseñas ni códigos; si te los pide, detente y avísame.
```

Después de este paso, tú: toca **Download**, guarda el archivo `.p8` (Apple
solo deja bajarlo una vez) y sigue con el prompt 5.

---

## 4 · Supabase: correos de código en inglés

```
Estás en supabase.com/dashboard con mi sesión iniciada. Abre el proyecto MonAvi (id jfhevxztsvnlsuwkwtmd) → Authentication → Emails → Templates.

La app guarda el idioma de cada persona en los datos del usuario como "language" ("es" o "en"). Quiero que los correos salgan en inglés cuando language es "en", y que el español quede EXACTAMENTE como está hoy.

Haz esto en cada plantilla que tenga contenido personalizado en español (por lo menos "Confirm signup" y "Reset password"; revisa también "Magic Link" y "Change Email Address"):

1. Antes de cambiar nada, copia y guárdate el Subject y el Body actuales tal cual.
2. Subject: reemplázalo por
{{ if eq .Data.language "en" }}<subject en inglés>{{ else }}<subject actual sin cambios>{{ end }}
   Para el subject en inglés traduce el actual (por ejemplo "Tu código de MonAvi" → "Your MonAvi code").
3. Body: reemplázalo por
{{ if eq .Data.language "en" }}
<versión en inglés>
{{ else }}
<body actual completo, sin cambiar nada>
{{ end }}
   La versión en inglés debe ser la traducción del body actual, con el mismo diseño HTML y las MISMAS variables que use el original ({{ .Token }}, {{ .ConfirmationURL }}, {{ .SiteURL }}, etc.). No inventes variables nuevas. Tono cercano y corto, en inglés de EE. UU.
4. Guarda cada plantilla.

Reglas: no cambies la configuración de SMTP, ni los proveedores de Auth, ni ninguna otra sección. No escribas contraseñas ni códigos. Al terminar, muéstrame el Subject final de cada plantilla que cambiaste y confirma que el bloque {{ else }} contiene el español original intacto.
```

---

## 5 · Supabase: secretos de DeviceCheck

```
Estás en supabase.com/dashboard con mi sesión iniciada. Abre el proyecto MonAvi (id jfhevxztsvnlsuwkwtmd) → Edge Functions → Secrets (o Project Settings → Edge Functions → Secrets).

Agrega este secreto:
- Name: DEVICECHECK_KEY_ID
- Value: <PEGA AQUÍ EL KEY ID DEL PASO 3>
Guarda.

Después agrega una fila nueva con el Name DEVICECHECK_PRIVATE_KEY y DEJA EL VALOR VACÍO: detente ahí y avísame, porque el valor (la clave privada) lo pego yo mismo.

Reglas: no cambies ni borres los otros secretos. No leas ni copies valores de secretos existentes. No escribas contraseñas ni códigos.
```

Después, tú: abre el `.p8` con TextEdit, copia **todo** su contenido
(incluidas las líneas `-----BEGIN PRIVATE KEY-----` y `-----END PRIVATE KEY-----`),
pégalo como valor de `DEVICECHECK_PRIVATE_KEY` y guarda. No me lo pegues en el
chat. Con eso DeviceCheck queda funcionando sin publicar nada más.

---

## Lo que no puede hacer Chrome

- **Capturas en inglés:** tienes que sacarlas desde el iPhone con la app en inglés.
  Si me las mandas, te las devuelvo con texto y en el tamaño de Apple.
- **Subir el build 1.1.0 y mandarlo a revisión:** lo haces tú desde Xcode y
  App Store Connect cuando esté compilado y probado.
