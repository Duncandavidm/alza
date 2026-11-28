# Correos de Supabase en inglés (1.1.0)

Desde la 1.1.0 la app guarda el idioma de cada persona en los datos del
usuario de Auth (`language`: `"es"` o `"en"`) al crear la cuenta y al
cambiar el idioma en Ajustes. Las plantillas de correo de Supabase pueden
leerlo con `.Data.language`.

## Dónde se cambia

Supabase → proyecto MonAvi → **Authentication → Emails → Templates**.

En cada plantilla que use la app (por ejemplo **Reset password** y
**Confirm signup**), envuelve el texto actual así. El español queda igual
que hoy; el inglés se agrega:

**Subject:**

```
{{ if eq .Data.language "en" }}Your MonAvi code{{ else }}Tu código de MonAvi{{ end }}
```

**Body (ejemplo con el código de 6 dígitos):**

```html
{{ if eq .Data.language "en" }}
  <h2>Your MonAvi code</h2>
  <p>Use this code to continue in the app:</p>
  <p style="font-size:28px;font-weight:700;letter-spacing:6px">{{ .Token }}</p>
  <p>If you didn't ask for it, you can ignore this email.</p>
{{ else }}
  <!-- Aquí va el texto en español que ya tienes hoy, sin cambios. -->
{{ end }}
```

Quien no tenga `language` guardado (cuentas creadas antes de la 1.1.0)
recibe el español, como siempre.
