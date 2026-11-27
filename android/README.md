# MonAvi para Android

App nativa (Kotlin + Jetpack Compose) que usa el mismo Supabase que la app de iPhone.

## Abrir y correr

1. Instala Android Studio (Ladybug o más nuevo).
2. **File → Open** y elige la carpeta `android/` del repositorio.
3. Espera a que termine "Gradle sync" y toca ▶︎ con un emulador o un teléfono conectado.

Desde la terminal:

```bash
cd android
./gradlew assembleDebug        # APK de prueba en app/build/outputs/apk/debug/
./gradlew bundleRelease        # AAB para Play Store (necesita la llave de firma)
```

## Qué incluye (fase 1)

- Entrar y crear cuenta con correo y contraseña; recuperar contraseña con código por correo.
- Onboarding corto (nombre, cuenta principal, ahorros, primer presupuesto).
- Hoy, Anotar movimiento (con el guardián de saldo negativo), Resumen del mes y Presupuestos.
- Ajustes: documentos legales, soporte, cerrar sesión y eliminar cuenta.

## Pendiente antes de publicar

- Suscripción con Google Play Billing + verificación en el servidor (`verify-google-purchase`).
- Comercios aliados y canjes (con verificación de correo).
- Escaneo de facturas DGI y cashback.
- Análisis e IA (insights, preguntas, voz).
- Llave de firma de subida (upload key) y ficha de Play Store.
