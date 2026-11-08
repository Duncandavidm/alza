# Correos de MonAvi (Supabase Auth)

Pegar en Supabase > Authentication > Emails > Templates. Asunto y archivo para cada uno:

| Plantilla en Supabase | Asunto | Archivo |
|---|---|---|
| Magic Link | `Tu código de MonAvi: {{ .Token }}` | `codigo-de-acceso.html` |
| Confirm signup | `Confirma tu correo en MonAvi` | `confirmar-registro.html` |
| Reset Password | `Tu código para cambiar la contraseña: {{ .Token }}` | `restablecer-contrasena.html` |
| Change Email Address | `Confirma tu nuevo correo en MonAvi` | `cambiar-correo.html` |
| Reauthentication | `Tu código de seguridad de MonAvi: {{ .Token }}` | `reautenticacion.html` |

"Magic Link" es el que usa la app para el codigo de 6 digitos antes del primer canje (muestra {{ .Token }}, no un enlace).
