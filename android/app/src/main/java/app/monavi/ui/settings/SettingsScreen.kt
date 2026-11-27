package app.monavi.ui.settings

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.monavi.BuildConfig
import app.monavi.data.Backend
import app.monavi.data.Repo
import app.monavi.ui.theme.Brand
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.launch

/** Ajustes: tu cuenta, documentos legales, soporte, cerrar sesión y eliminar cuenta. */
@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    val email = Backend.client.auth.currentUserOrNull()?.email

    LaunchedEffect(Unit) { name = runCatching { Repo.profile()?.fullName }.getOrNull() }

    fun open(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))

    Column(
        Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Ajustes", style = MaterialTheme.typography.headlineLarge)
        Group {
            Text(name ?: "Tu cuenta", fontWeight = FontWeight.Bold)
            email?.let { Text(it, color = Brand.secondaryText) }
        }
        Group {
            Row("Política de privacidad") { open("https://monavi.maday.app/privacy") }
            HorizontalDivider(color = Brand.border)
            Row("Términos de uso") { open("https://monavi.maday.app/terms") }
            HorizontalDivider(color = Brand.border)
            Row("Soporte") { open("https://monavi.maday.app/support") }
            HorizontalDivider(color = Brand.border)
            Row("Escríbenos: hola@maday.app") { open("mailto:hola@maday.app") }
        }
        Group {
            Row("Cerrar sesión") { scope.launch { runCatching { Backend.client.auth.signOut() } } }
            HorizontalDivider(color = Brand.border)
            Row("Eliminar mi cuenta", color = Brand.alert) { confirmDelete = true }
        }
        Text("MonAvi para Android ${BuildConfig.VERSION_NAME}", color = Brand.secondaryText)
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { if (!deleting) confirmDelete = false },
            title = { Text("¿Eliminar tu cuenta?") },
            text = { Text("Se borran tu cuenta y todos tus datos de MonAvi de forma permanente. Si tienes una suscripción, cancélala también en Google Play.") },
            confirmButton = {
                TextButton(enabled = !deleting, onClick = {
                    deleting = true
                    scope.launch { runCatching { Repo.deleteMyAccount() }; deleting = false; confirmDelete = false }
                }) { Text("Eliminar", color = Brand.alert) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }, enabled = !deleting) { Text("Cancelar") } },
        )
    }
}

@Composable
private fun Group(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(Brand.card, RoundedCornerShape(18.dp)).padding(horizontal = 16.dp, vertical = 8.dp)) {
        content()
    }
}

@Composable
private fun Row(label: String, color: Color = Color.Unspecified, onClick: () -> Unit) {
    Text(label, color = color, modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 14.dp))
}
