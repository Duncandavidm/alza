package app.monavi.ui.auth

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.monavi.R
import app.monavi.data.Backend
import app.monavi.ui.theme.Brand
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import kotlinx.coroutines.launch

/** Entrar o crear cuenta con correo y contraseña (sin Google, como pidió el equipo). */
@Composable
fun AuthScreen() {
    var signUp by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var info by remember { mutableStateOf<String?>(null) }
    var resetting by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun submit() {
        error = null; info = null
        val mail = email.trim().lowercase()
        if (!mail.contains("@")) { error = "Escribe un correo válido."; return }
        if (signUp) {
            passwordProblem(password)?.let { error = it; return }
            if (password != confirm) { error = "Las contraseñas no coinciden."; return }
        }
        busy = true
        scope.launch {
            try {
                if (signUp) {
                    Backend.client.auth.signUpWith(Email) { this.email = mail; this.password = password }
                    if (Backend.client.auth.currentSessionOrNull() == null) {
                        info = "Te enviamos un correo a $mail para confirmar tu cuenta. Confírmala y vuelve a entrar."
                        signUp = false
                    }
                } else {
                    Backend.client.auth.signInWith(Email) { this.email = mail; this.password = password }
                }
            } catch (e: Exception) {
                error = friendlyAuthError(e)
            } finally {
                busy = false
            }
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Brand.primaryDark, Brand.darkSurface)))
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(36.dp))
            Box(
                Modifier.size(84.dp).background(Brand.primary, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Image(painterResource(R.drawable.ic_launcher_foreground), null, Modifier.size(84.dp))
            }
            Spacer(Modifier.height(16.dp))
            Text("MonAvi", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.ExtraBold)
            Text("Ordena. Ahorra. Avanza.", color = Brand.accentOnDark, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(32.dp))

            Surface(shape = RoundedCornerShape(24.dp), color = Color.White, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(if (signUp) "Crea tu cuenta" else "Entra a tu cuenta", style = MaterialTheme.typography.titleLarge)
                    OutlinedTextField(
                        value = email, onValueChange = { email = it }, label = { Text("Correo") },
                        singleLine = true, modifier = Modifier.fillMaxWidth(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    )
                    OutlinedTextField(
                        value = password, onValueChange = { password = it }, label = { Text("Contraseña") },
                        singleLine = true, modifier = Modifier.fillMaxWidth(),
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        supportingText = if (signUp) ({ Text("Al menos 8 caracteres, con letras y números.") }) else null,
                    )
                    if (signUp) {
                        OutlinedTextField(
                            value = confirm, onValueChange = { confirm = it }, label = { Text("Repite la contraseña") },
                            singleLine = true, modifier = Modifier.fillMaxWidth(),
                            visualTransformation = PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        )
                    }
                    error?.let { Text(it, color = Brand.alert, style = MaterialTheme.typography.bodyMedium) }
                    info?.let { Text(it, color = Brand.primaryDark, style = MaterialTheme.typography.bodyMedium) }
                    Button(
                        onClick = ::submit, enabled = !busy,
                        modifier = Modifier.fillMaxWidth().height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Brand.primary),
                    ) {
                        if (busy) CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                        else Text(if (signUp) "Crear cuenta" else "Entrar")
                    }
                    if (!signUp) {
                        TextButton(onClick = { resetting = true }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                            Text("¿Olvidaste tu contraseña?", color = Brand.primaryDark)
                        }
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            TextButton(onClick = { signUp = !signUp; error = null; info = null }) {
                Text(
                    if (signUp) "¿Ya tienes cuenta? Entra" else "¿Nuevo en MonAvi? Crea tu cuenta",
                    color = Color.White, fontWeight = FontWeight.SemiBold,
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "Al continuar aceptas los Términos de uso y la Política de privacidad de MonAvi.",
                color = Color.White.copy(alpha = 0.6f), textAlign = TextAlign.Center, fontSize = 12.sp,
            )
        }
    }

    if (resetting) PasswordResetDialog(initialEmail = email, onClose = { resetting = false })
}

/** Igual que iPhone: código de recuperación por correo y nueva contraseña. */
@Composable
private fun PasswordResetDialog(initialEmail: String, onClose: () -> Unit) {
    var email by remember { mutableStateOf(initialEmail) }
    var code by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var step by remember { mutableStateOf(0) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    AlertDialog(
        onDismissRequest = { if (!busy) onClose() },
        title = { Text("Recuperar contraseña") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                when (step) {
                    0 -> {
                        Text("Te enviaremos un código a tu correo.")
                        OutlinedTextField(email, { email = it }, label = { Text("Correo") }, singleLine = true)
                    }
                    else -> {
                        Text("Escribe el código que te llegó a ${email.trim()} y tu nueva contraseña.")
                        OutlinedTextField(code, { code = it.filter(Char::isDigit).take(8) }, label = { Text("Código") }, singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
                        OutlinedTextField(newPassword, { newPassword = it }, label = { Text("Nueva contraseña") }, singleLine = true,
                            visualTransformation = PasswordVisualTransformation())
                    }
                }
                message?.let { Text(it, color = Brand.alert) }
            }
        },
        confirmButton = {
            TextButton(enabled = !busy, onClick = {
                message = null
                busy = true
                scope.launch {
                    try {
                        if (step == 0) {
                            Backend.client.auth.resetPasswordForEmail(email.trim().lowercase())
                            step = 1
                        } else {
                            passwordProblem(newPassword)?.let { message = it; return@launch }
                            Backend.client.auth.verifyEmailOtp(type = OtpType.Email.RECOVERY, email = email.trim().lowercase(), token = code.trim())
                            Backend.client.auth.updateUser { password = newPassword }
                            onClose()
                        }
                    } catch (e: Exception) {
                        message = if (step == 0) "No pudimos enviar el código. Revisa el correo e intenta de nuevo." else "El código no es válido o ya venció."
                    } finally {
                        busy = false
                    }
                }
            }) { Text(if (step == 0) "Enviar código" else "Guardar") }
        },
        dismissButton = { TextButton(onClick = onClose, enabled = !busy) { Text("Cancelar") } },
    )
}

/** Misma regla que iPhone: 8+ caracteres, con letras y números. */
fun passwordProblem(password: String): String? = when {
    password.length < 8 -> "La contraseña necesita al menos 8 caracteres."
    password.none(Char::isLetter) || password.none(Char::isDigit) -> "La contraseña necesita letras y números."
    else -> null
}

private fun friendlyAuthError(e: Exception): String {
    val text = e.message.orEmpty().lowercase()
    return when {
        "invalid login credentials" in text || "invalid_credentials" in text -> "Correo o contraseña incorrectos."
        "email not confirmed" in text -> "Confirma tu correo antes de entrar (revisa tu bandeja)."
        "already registered" in text || "user_already_exists" in text -> "Ya existe una cuenta con ese correo. Entra o recupera tu contraseña."
        "network" in text || "unable to resolve" in text || "timeout" in text -> "Sin conexión. Revisa tu internet e intenta de nuevo."
        else -> "No pudimos completar la operación. Intenta de nuevo."
    }
}
