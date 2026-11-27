package app.monavi.ui.today

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.monavi.data.Account
import app.monavi.data.Category
import app.monavi.data.FinanceTransaction
import app.monavi.data.Fmt
import app.monavi.data.MovementType
import app.monavi.data.Repo
import app.monavi.ui.theme.Brand
import kotlinx.coroutines.launch
import java.math.BigDecimal

/**
 * "Anotar movimiento": monto con teclado propio, tipo, categoría opcional,
 * descripción y cuenta. Si `existing` no es null, edita ese movimiento.
 * El guardián: si el gasto deja una cuenta en negativo, pregunta de dónde
 * salió el dinero antes de guardar (igual que iPhone 1.0.9).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickAddSheet(
    accounts: List<Account>,
    defaultAccountId: String?,
    existing: FinanceTransaction? = null,
    initialType: MovementType = MovementType.GASTO,
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
) {
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val invoiceLocked = existing?.isFromInvoice == true

    var type by remember { mutableStateOf(existing?.movementType?.let { if (it in MovementType.quickAdd) it else MovementType.GASTO } ?: initialType) }
    var amountText by remember { mutableStateOf(existing?.amount?.abs()?.stripTrailingZeros()?.toPlainString() ?: "") }
    var category by remember { mutableStateOf(existing?.category) }
    var description by remember { mutableStateOf(existing?.description ?: "") }
    var accountId by remember { mutableStateOf(existing?.accountId ?: defaultAccountId ?: accounts.firstOrNull()?.id) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var askNoMoney by remember { mutableStateOf(false) }
    var allowNegative by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf<String?>(null) }

    val magnitude = Fmt.parseAmount(amountText)
    val account = accounts.firstOrNull { it.id == accountId }
    val balanceAfter: BigDecimal? =
        if (existing == null && !type.isInflow && magnitude != null && account != null && !account.type.isLiability)
            account.balance - magnitude else null
    val alternatives = accounts.filter { other ->
        other.id != accountId && !other.type.isLiability && magnitude != null && other.balance >= magnitude
    }

    fun save() {
        // Se recalcula con el estado actual (la cuenta pudo cambiar en el diálogo).
        val amount = Fmt.parseAmount(amountText) ?: return
        val acc = accountId ?: return
        val current = accounts.firstOrNull { it.id == acc }
        val after = if (existing == null && !type.isInflow && current != null && !current.type.isLiability) current.balance - amount else null
        if (after != null && after.signum() < 0 && !allowNegative) { askNoMoney = true; return }
        busy = true; error = null
        scope.launch {
            try {
                if (existing != null) Repo.updateTransaction(existing, amount, type, category, description)
                else Repo.addTransaction(acc, amount, type, category, description)
                onSaved()
            } catch (e: Exception) {
                error = "No se pudo guardar. Revisa tu conexión."
            } finally {
                busy = false
            }
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet, containerColor = Brand.background) {
        Column(
            Modifier.fillMaxWidth().navigationBarsPadding().imePadding().padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(if (existing == null) "Anotar movimiento" else "Editar movimiento", style = MaterialTheme.typography.titleMedium)

            if (!invoiceLocked) {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    MovementType.quickAdd.forEachIndexed { i, t ->
                        SegmentedButton(
                            selected = type == t,
                            onClick = { type = t; allowNegative = false },
                            shape = SegmentedButtonDefaults.itemShape(i, MovementType.quickAdd.size),
                        ) { Text("${t.emoji} ${t.label}") }
                    }
                }
            }

            val sign = if (type.isInflow) "+" else "−"
            Text(
                if (amountText.isEmpty()) "$0" else "$sign$${amountText}",
                fontSize = 46.sp, fontWeight = FontWeight.ExtraBold,
                color = if (type.isInflow) Brand.primaryDark else Brand.alert,
            )
            if (invoiceLocked) Text("Monto de la factura · no se puede cambiar", color = Brand.secondaryText, fontSize = 13.sp)

            if (existing == null && accounts.size > 1 && account != null) {
                AccountPicker(accounts, account) { accountId = it.id; allowNegative = false }
            }
            if (balanceAfter != null && account != null) {
                when {
                    balanceAfter.signum() < 0 -> Text(
                        "⚠️ «${account.name}» quedaría en -${Fmt.money(balanceAfter.abs())}. ¿De dónde sale este dinero?",
                        color = Brand.alert, fontSize = 13.sp, textAlign = TextAlign.Center,
                    )
                    account.balance.signum() > 0 && balanceAfter < account.balance.multiply(BigDecimal("0.1")) -> Text(
                        "Te quedarían solo ${Fmt.money(balanceAfter)} en «${account.name}».",
                        color = Color(0xFFE67700), fontSize = 13.sp, textAlign = TextAlign.Center,
                    )
                }
            }
            note?.let { if (type.isInflow) Text(it, color = Brand.secondaryText, fontSize = 13.sp, textAlign = TextAlign.Center) }

            val cats = if (type.isInflow) Category.incomes else Category.expenses
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(horizontal = 2.dp)) {
                items(cats) { c ->
                    val selected = category.equals(c.raw, ignoreCase = true)
                    val tint = Color(c.hex)
                    Box(
                        Modifier
                            .background(if (selected) tint.copy(alpha = 0.18f) else Brand.card, RoundedCornerShape(50))
                            .border(1.5.dp, if (selected) tint else Brand.border, RoundedCornerShape(50))
                            .clickable { category = if (selected) null else c.raw }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    ) { Text("${c.emoji} ${c.raw}", fontSize = 14.sp) }
                }
            }

            OutlinedTextField(
                description, { description = it }, placeholder = { Text("¿Qué fue? ej. Almuerzo") },
                singleLine = true, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp),
            )

            if (!invoiceLocked) Keypad { key ->
                amountText = when (key) {
                    "⌫" -> amountText.dropLast(1)
                    "." -> if ("." in amountText) amountText else if (amountText.isEmpty()) "0." else "$amountText."
                    else -> {
                        val next = amountText + key
                        val decimals = next.substringAfter('.', "")
                        if ("." in next && decimals.length > 2) amountText else next.trimStart('0').ifEmpty { "0" }.let {
                            if (it.startsWith(".")) "0$it" else it
                        }
                    }
                }
                allowNegative = false
            }

            error?.let { Text(it, color = Brand.alert) }
            Button(
                onClick = ::save, enabled = magnitude != null && accountId != null && !busy,
                modifier = Modifier.fillMaxWidth().height(52.dp), shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = if (type.isInflow) Brand.primary else Brand.alert),
            ) { Text(if (existing == null) "Guardar" else "Guardar cambios") }
            Spacer(Modifier.height(8.dp))
        }
    }

    if (askNoMoney && account != null && magnitude != null && balanceAfter != null) {
        AlertDialog(
            onDismissRequest = { askNoMoney = false },
            title = { Text("Esta cuenta no tiene ese dinero") },
            text = {
                Text("«${account.name}» tiene ${Fmt.money(account.balance)} y este gasto es de ${Fmt.money(magnitude)}: quedaría en -${Fmt.money(balanceAfter.abs())}. No se puede gastar dinero que no hay. ¿De dónde salió?")
            },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    alternatives.take(3).forEach { other ->
                        TextButton(onClick = { askNoMoney = false; accountId = other.id; save() }) { Text("Lo pagué con ${other.name}") }
                    }
                    TextButton(onClick = {
                        askNoMoney = false
                        type = MovementType.INGRESO; amountText = ""; description = ""; category = null
                        note = "Anota primero de dónde vino el dinero (sueldo, venta, préstamo…). Después anota el gasto."
                    }) { Text("Primero anoto el ingreso") }
                    TextButton(onClick = { askNoMoney = false; allowNegative = true; save() }) { Text("Guardar igual", color = Brand.alert) }
                    TextButton(onClick = { askNoMoney = false }) { Text("Cancelar") }
                }
            },
        )
    }
}

@Composable
private fun AccountPicker(accounts: List<Account>, selected: Account, onPick: (Account) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Text(
            "De: ${selected.name} ▾",
            modifier = Modifier
                .background(Brand.card, RoundedCornerShape(50))
                .border(1.dp, Brand.border, RoundedCornerShape(50))
                .clickable { open = true }
                .padding(horizontal = 14.dp, vertical = 8.dp),
            fontWeight = FontWeight.SemiBold,
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            accounts.forEach { a ->
                DropdownMenuItem(
                    text = { Text("${a.name} · ${Fmt.money(if (a.type.isLiability) a.balance.abs() else a.balance)}") },
                    onClick = { open = false; onPick(a) },
                )
            }
        }
    }
}

@Composable
private fun Keypad(onKey: (String) -> Unit) {
    val rows = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf(".", "0", "⌫"))
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { key ->
                    Box(
                        Modifier
                            .weight(1f)
                            .height(52.dp)
                            .background(Brand.card, RoundedCornerShape(14.dp))
                            .clickable { onKey(key) },
                        contentAlignment = Alignment.Center,
                    ) { Text(key, fontSize = 22.sp, fontWeight = FontWeight.SemiBold) }
                }
            }
        }
    }
}
