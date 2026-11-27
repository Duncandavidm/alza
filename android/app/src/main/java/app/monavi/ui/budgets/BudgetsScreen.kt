package app.monavi.ui.budgets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.monavi.data.BudgetProgress
import app.monavi.data.Category
import app.monavi.data.CategoryDisplay
import app.monavi.data.Fmt
import app.monavi.data.Repo
import app.monavi.ui.theme.Brand
import kotlinx.coroutines.launch

/** Presupuestos: cuánto llevas de cada límite, con el color suave de la categoría. */
@Composable
fun BudgetsScreen() {
    var progresses by remember { mutableStateOf<List<BudgetProgress>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var adding by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<BudgetProgress?>(null) }
    var reload by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(reload) {
        progresses = runCatching { Repo.budgetProgress() }.getOrDefault(emptyList())
        loading = false
    }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            Modifier.fillMaxSize().statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item { Text("Presupuestos", style = MaterialTheme.typography.headlineLarge) }
            if (progresses.isEmpty() && !loading) {
                item {
                    Column(Modifier.fillMaxWidth().background(Brand.card, RoundedCornerShape(20.dp)).padding(20.dp)) {
                        Text("Sin presupuestos todavía", fontWeight = FontWeight.Bold)
                        Text("Ponle un límite semanal o mensual a una categoría para no pasarte.", color = Brand.secondaryText)
                    }
                }
            }
            items(progresses, key = { it.budget.id }) { p ->
                val tint = Color(CategoryDisplay.color(p.budget.category))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .background(tint.copy(alpha = 0.14f), RoundedCornerShape(18.dp))
                        .clickable { deleting = p }
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(CategoryDisplay.emoji(p.budget.category), fontSize = 20.sp)
                        Spacer(Modifier.width(8.dp))
                        Text(p.budget.category, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        Text(if (p.budget.period == "weekly") "Semanal" else "Mensual", color = Brand.secondaryText, fontSize = 13.sp)
                    }
                    LinearProgressIndicator(
                        progress = { p.ratio.coerceIn(0.0, 1.0).toFloat() },
                        modifier = Modifier.fillMaxWidth(),
                        color = when (p.status) {
                            BudgetProgress.Status.OVER -> Brand.alert
                            BudgetProgress.Status.WARNING -> Color(0xFFE67700)
                            BudgetProgress.Status.ON_TRACK -> Brand.primary
                        },
                        trackColor = Color.White.copy(alpha = 0.7f),
                    )
                    Row {
                        Text("${Fmt.money(p.spent)} de ${Fmt.money(p.budget.limitAmount)}", color = Brand.secondaryText, fontSize = 13.sp, modifier = Modifier.weight(1f))
                        when (p.status) {
                            BudgetProgress.Status.OVER -> Text("Te pasaste", color = Brand.alert, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            BudgetProgress.Status.WARNING -> Text("Cuidado", color = Color(0xFFE67700), fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            else -> {}
                        }
                    }
                }
            }
        }
        FloatingActionButton(
            onClick = { adding = true },
            modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp),
            containerColor = Brand.primary, contentColor = Color.White,
        ) { Icon(Icons.Filled.Add, "Agregar presupuesto") }
    }

    if (adding) {
        AddBudgetDialog(
            taken = progresses.map { it.budget.category.lowercase() }.toSet(),
            onClose = { adding = false },
            onSaved = { adding = false; reload++ },
        )
    }

    deleting?.let { p ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("¿Eliminar el presupuesto de ${p.budget.category}?") },
            text = { Text("Tus movimientos no se borran.") },
            confirmButton = {
                TextButton(onClick = {
                    deleting = null
                    scope.launch { runCatching { Repo.deleteBudget(p.budget.id) }; reload++ }
                }) { Text("Eliminar", color = Brand.alert) }
            },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("Cancelar") } },
        )
    }
}

@Composable
private fun AddBudgetDialog(taken: Set<String>, onClose: () -> Unit, onSaved: () -> Unit) {
    var category by remember { mutableStateOf<String?>(null) }
    var amount by remember { mutableStateOf("") }
    var weekly by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val options = Category.expenses.filter { it.raw.lowercase() !in taken }

    AlertDialog(
        onDismissRequest = onClose,
        title = { Text("Nuevo presupuesto") },
        text = {
            Column(Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    amount, { amount = it }, label = { Text("Límite (US$)") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(false to "Mensual", true to "Semanal").forEach { (w, label) ->
                        Text(
                            label,
                            modifier = Modifier
                                .background(if (weekly == w) Brand.mint else Brand.background, RoundedCornerShape(50))
                                .clickable { weekly = w }
                                .padding(horizontal = 14.dp, vertical = 8.dp),
                            fontWeight = if (weekly == w) FontWeight.Bold else FontWeight.Normal,
                        )
                    }
                }
                Text("Categoría", fontWeight = FontWeight.SemiBold)
                options.forEach { c ->
                    Text(
                        "${c.emoji}  ${c.raw}",
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(if (category == c.raw) Color(c.hex).copy(alpha = 0.18f) else Color.Transparent, RoundedCornerShape(10.dp))
                            .clickable { category = c.raw }
                            .padding(10.dp),
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !busy && category != null && Fmt.parseAmount(amount) != null,
                onClick = {
                    busy = true
                    scope.launch {
                        runCatching { Repo.addBudget(category!!, Fmt.parseAmount(amount)!!, if (weekly) "weekly" else "monthly") }
                        busy = false
                        onSaved()
                    }
                },
            ) { Text("Guardar") }
        },
        dismissButton = { TextButton(onClick = onClose) { Text("Cancelar") } },
    )
}
