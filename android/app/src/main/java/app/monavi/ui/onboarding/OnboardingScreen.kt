package app.monavi.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.monavi.data.AccountType
import app.monavi.data.Category
import app.monavi.data.Fmt
import app.monavi.data.Repo
import app.monavi.ui.theme.Brand
import kotlinx.coroutines.launch
import java.math.BigDecimal

/**
 * Onboarding corto: nombre, cuenta principal con su saldo, ahorros y un
 * primer presupuesto. Igual que iPhone deja la cuenta lista para anotar.
 */
@Composable
fun OnboardingScreen(onDone: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var mainBalance by remember { mutableStateOf("") }
    var savings by remember { mutableStateOf("") }
    var foodBudget by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    Column(
        Modifier
            .fillMaxSize()
            .background(Brand.background)
            .statusBarsPadding()
            .navigationBarsPadding()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Spacer(Modifier.height(12.dp))
        Text("¡Bienvenido a MonAvi! 👋", style = MaterialTheme.typography.headlineMedium)
        Text("Tres datos y empiezas a ordenar tu dinero.", color = Brand.secondaryText)

        OutlinedTextField(name, { name = it }, label = { Text("¿Cómo te llamas?") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(
            mainBalance, { mainBalance = it }, label = { Text("¿Cuánto tienes hoy en tu cuenta principal?") },
            placeholder = { Text("ej. 850.00") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        )
        OutlinedTextField(
            savings, { savings = it }, label = { Text("¿Y en ahorros? (opcional)") },
            singleLine = true, modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        )
        OutlinedTextField(
            foodBudget, { foodBudget = it }, label = { Text("¿Cuánto quieres gastar al mes en comida? (opcional)") },
            singleLine = true, modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        )
        error?.let { Text(it, color = Brand.alert) }
        Spacer(Modifier.height(8.dp))
        Button(
            enabled = !busy,
            onClick = {
                error = null
                busy = true
                scope.launch {
                    try {
                        val existing = Repo.accounts()
                        if (existing.isEmpty()) {
                            Repo.createAccount("Cuenta principal", AccountType.CHECKING, mainBalance.toMoney())
                            val saved = mainBalanceOrNull(savings)
                            if (saved != null) Repo.createAccount("Ahorros", AccountType.SAVINGS, saved)
                        }
                        Fmt.parseAmount(foodBudget)?.let { Repo.addBudget(Category.FOOD.raw, it) }
                        Repo.completeOnboarding(name)
                        onDone()
                    } catch (e: Exception) {
                        error = "No pudimos guardar. Revisa tu conexión e intenta de nuevo."
                    } finally {
                        busy = false
                    }
                }
            },
            modifier = Modifier.fillMaxWidth().height(54.dp),
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Brand.primary),
        ) { Text("Empezar") }
    }
}

private fun String.toMoney(): BigDecimal = trim().replace(",", ".").toBigDecimalOrNull() ?: BigDecimal.ZERO
private fun mainBalanceOrNull(text: String): BigDecimal? = Fmt.parseAmount(text)
