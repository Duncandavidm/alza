package app.monavi.ui.today

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.monavi.data.Account
import app.monavi.data.BudgetProgress
import app.monavi.data.CategoryDisplay
import app.monavi.data.FinanceTransaction
import app.monavi.data.Fmt
import app.monavi.data.Repo
import app.monavi.ui.components.Card
import app.monavi.ui.components.CategoryIcon
import app.monavi.ui.theme.Brand
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val dayFormat = DateTimeFormatter.ofPattern("EEEE d 'de' MMMM", Locale.forLanguageTag("es-PA"))
private val timeFormat = DateTimeFormatter.ofPattern("h:mm a", Locale.forLanguageTag("es-PA"))

/** Hoy: lo que entró y salió hoy, tus cuentas, tus presupuestos y los movimientos. */
@Composable
fun TodayScreen() {
    var accounts by remember { mutableStateOf<List<Account>>(emptyList()) }
    var transactions by remember { mutableStateOf<List<FinanceTransaction>>(emptyList()) }
    var budgets by remember { mutableStateOf<List<BudgetProgress>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var adding by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<FinanceTransaction?>(null) }
    var deleting by remember { mutableStateOf<FinanceTransaction?>(null) }
    var reload by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(reload) {
        try {
            accounts = Repo.accounts()
            transactions = Repo.transactionsOn(LocalDate.now())
            budgets = Repo.budgetProgress()
            Repo.userCategories()
            error = null
        } catch (e: Exception) {
            error = "No pudimos cargar tus datos. Desliza para reintentar o revisa tu conexión."
        } finally {
            loading = false
        }
    }

    val income = transactions.filter { it.movementType.isInflow }.fold(BigDecimal.ZERO) { a, t -> a + t.amount }
    val expense = transactions.filter { !it.movementType.isInflow }.fold(BigDecimal.ZERO) { a, t -> a + t.amount.abs() }
    val defaultAccount = transactions.firstOrNull()?.accountId?.takeIf { id -> accounts.any { it.id == id && !it.type.isReserve } }
        ?: accounts.firstOrNull { !it.type.isReserve && !it.type.isLiability }?.id ?: accounts.firstOrNull()?.id

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            Modifier.fillMaxSize().statusBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 100.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Column {
                    Text("Hoy", style = MaterialTheme.typography.headlineLarge)
                    Text(LocalDate.now().format(dayFormat).replaceFirstChar { it.uppercase() }, color = Brand.secondaryText)
                }
            }
            item { TotalsCard(income, expense) }
            error?.let { msg -> item { Text(msg, color = Brand.alert) } }
            if (accounts.isNotEmpty()) item { AccountsStrip(accounts) }
            if (budgets.isNotEmpty()) item { BudgetBars(budgets) }
            item { Text("Movimientos de hoy", style = MaterialTheme.typography.titleMedium) }
            if (transactions.isEmpty() && !loading) {
                item {
                    Card {
                        Text("Todavía no anotas nada hoy.", fontWeight = FontWeight.SemiBold)
                        Text("Toca «Anotar» y registra tu primer gasto en segundos.", color = Brand.secondaryText)
                    }
                }
            }
            items(transactions, key = { it.id }) { tx ->
                SwipeRow(
                    onDelete = { deleting = tx },
                    onEdit = { editing = tx },
                ) { TransactionRow(tx, accounts) }
            }
        }

        ExtendedFloatingActionButton(
            onClick = { adding = true },
            modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp),
            containerColor = Brand.primary, contentColor = Color.White,
            icon = { Icon(Icons.Filled.Add, null) },
            text = { Text("Anotar") },
        )
    }

    if (adding || editing != null) {
        QuickAddSheet(
            accounts = accounts,
            defaultAccountId = defaultAccount,
            existing = editing,
            onDismiss = { adding = false; editing = null },
            onSaved = { adding = false; editing = null; reload++ },
        )
    }

    deleting?.let { tx ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("¿Eliminar este movimiento?") },
            text = {
                Text(if (tx.isFromInvoice) "Viene de una factura escaneada: si lo eliminas, también se quita el cashback de esa factura." else "Se ajusta el saldo de la cuenta.")
            },
            confirmButton = {
                TextButton(onClick = {
                    deleting = null
                    scope.launch { runCatching { Repo.deleteTransaction(tx) }; reload++ }
                }) { Text("Eliminar", color = Brand.alert) }
            },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("Cancelar") } },
        )
    }
}

@Composable
private fun TotalsCard(income: BigDecimal, expense: BigDecimal) {
    val net = income - expense
    Column(
        Modifier
            .fillMaxWidth()
            .background(Brand.darkSurface, RoundedCornerShape(24.dp))
            .padding(20.dp),
    ) {
        Text("Balance de hoy", color = Brand.onDark.copy(alpha = 0.7f))
        Text(
            (if (net.signum() < 0) "−" else "") + Fmt.money(net.abs()),
            color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.ExtraBold,
        )
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Pill("Entró", Fmt.money(income), Brand.accentOnDark, Modifier.weight(1f))
            Pill("Salió", Fmt.money(expense), Color(0xFFFF9A8B), Modifier.weight(1f))
        }
    }
}

@Composable
private fun Pill(label: String, value: String, color: Color, modifier: Modifier) {
    Column(modifier.background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp)).padding(12.dp)) {
        Text(label, color = Brand.onDark.copy(alpha = 0.7f), fontSize = 13.sp)
        Text(value, color = color, fontWeight = FontWeight.Bold, fontSize = 18.sp)
    }
}

@Composable
private fun AccountsStrip(accounts: List<Account>) {
    Column {
        Text("Tus cuentas", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(accounts, key = { it.id }) { a ->
                val negative = !a.type.isLiability && a.balance.signum() < 0
                Column(
                    Modifier
                        .width(150.dp)
                        .background(if (negative) Brand.alert.copy(alpha = 0.1f) else Brand.card, RoundedCornerShape(18.dp))
                        .padding(14.dp),
                ) {
                    Text(a.name, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        if (a.type.isLiability) "Debes ${Fmt.money(a.balance.abs())}" else Fmt.money(a.balance),
                        fontWeight = FontWeight.Bold, fontSize = 18.sp,
                        color = if (negative) Brand.alert else Color.Unspecified,
                    )
                    Text(a.type.label, color = Brand.secondaryText, fontSize = 12.sp)
                }
            }
        }
    }
}

/** Barras "candy" de presupuesto con relleno pastel (como iPhone 1.0.9). */
@Composable
private fun BudgetBars(progresses: List<BudgetProgress>) {
    Column {
        Text("Tus presupuestos del mes", color = Brand.secondaryText, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
        Spacer(Modifier.height(8.dp))
        LazyRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            items(progresses, key = { it.budget.id }) { p ->
                val color = Color(CategoryDisplay.color(p.budget.category))
                val fill = if (p.status == BudgetProgress.Status.OVER) Brand.alert else color
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        Modifier.width(52.dp).height(96.dp).background(color.copy(alpha = 0.14f), RoundedCornerShape(50)),
                        contentAlignment = Alignment.BottomCenter,
                    ) {
                        Box(
                            Modifier
                                .width(48.dp)
                                .fillMaxHeight(p.ratio.coerceIn(0.1, 1.0).toFloat())
                                .padding(bottom = 2.dp)
                                .background(fill, RoundedCornerShape(50)),
                        )
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(CategoryDisplay.emoji(p.budget.category), fontSize = 20.sp)
                    Text(Fmt.money(p.spent), fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
                    Text("${(p.ratio * 100).toInt()}%", color = if (p.status == BudgetProgress.Status.OVER) Brand.alert else Brand.secondaryText, fontSize = 11.sp)
                }
            }
        }
    }
}

@Composable
fun TransactionRow(tx: FinanceTransaction, accounts: List<Account>) {
    val color = Color(CategoryDisplay.color(tx.category))
    Row(
        Modifier.fillMaxWidth().background(Brand.card, RoundedCornerShape(16.dp)).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CategoryIcon(if (tx.category != null) CategoryDisplay.emoji(tx.category) else tx.movementType.emoji, color)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(tx.description ?: tx.category ?: tx.movementType.label, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val accountName = accounts.firstOrNull { it.id == tx.accountId }?.name
            Text(
                listOfNotNull(tx.occurredAt.atZone(ZoneId.systemDefault()).format(timeFormat), tx.category, accountName, if (tx.isFromInvoice) "🧾 Factura" else null)
                    .joinToString(" · "),
                color = Brand.secondaryText, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        Text(
            (if (tx.movementType.isInflow) "+" else "−") + Fmt.money(tx.amount.abs()),
            fontWeight = FontWeight.Bold,
            color = if (tx.movementType.isInflow) Brand.primaryDark else Color.Unspecified,
        )
    }
}

/** Izquierda: eliminar. Derecha: editar (como iPhone). */
@Composable
fun SwipeRow(onDelete: () -> Unit, onEdit: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        when (value) {
            SwipeToDismissBoxValue.EndToStart -> onDelete()
            SwipeToDismissBoxValue.StartToEnd -> onEdit()
            else -> {}
        }
        false
    })
    SwipeToDismissBox(
        state = state,
        backgroundContent = {
            val toDelete = state.dismissDirection == SwipeToDismissBoxValue.EndToStart
            Box(
                Modifier.fillMaxSize().background(if (toDelete) Brand.alert else Brand.primary, RoundedCornerShape(16.dp)).padding(horizontal = 20.dp),
                contentAlignment = if (toDelete) Alignment.CenterEnd else Alignment.CenterStart,
            ) { Text(if (toDelete) "Eliminar" else "Editar", color = Color.White, fontWeight = FontWeight.Bold) }
        },
    ) {
        Box(Modifier.clickable { onEdit() }) { content() }
    }
}

