package app.monavi.ui.summary

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.monavi.data.CategoryDisplay
import app.monavi.data.FinanceTransaction
import app.monavi.data.Fmt
import app.monavi.data.Repo
import app.monavi.ui.components.CategoryIcon
import app.monavi.ui.theme.Brand
import java.math.BigDecimal
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

private data class CategoryTotal(val key: String, val total: BigDecimal, val count: Int)

private val monthFormat = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.forLanguageTag("es-PA"))

/** Resumen del mes: torta por categoría y filas pastel con su peso (como iPhone). */
@Composable
fun SummaryScreen() {
    var monthOffset by remember { mutableStateOf(0L) }
    var transactions by remember { mutableStateOf<List<FinanceTransaction>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    val month = ZonedDateTime.now().minusMonths(monthOffset)

    LaunchedEffect(monthOffset) {
        loading = true
        transactions = runCatching { Repo.monthTransactions(month) }.getOrDefault(emptyList())
        loading = false
    }

    val expenses = transactions.filter { !it.movementType.isInflow && it.movementRaw != "transferencia" }
    val income = transactions.filter { it.movementType.isInflow }.fold(BigDecimal.ZERO) { a, t -> a + t.amount }
    val totalSpent = expenses.fold(BigDecimal.ZERO) { a, t -> a + t.amount.abs() }
    val categories = expenses.groupBy { it.category?.trim().takeUnless { c -> c.isNullOrEmpty() } ?: "Otro" }
        .map { (key, items) -> CategoryTotal(key, items.fold(BigDecimal.ZERO) { a, t -> a + t.amount.abs() }, items.size) }
        .sortedByDescending { it.total }

    LazyColumn(
        Modifier.fillMaxSize().statusBarsPadding(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Resumen", style = MaterialTheme.typography.headlineLarge, modifier = Modifier.weight(1f))
                IconButton(onClick = { monthOffset++ }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Mes anterior") }
                Text(month.format(monthFormat).replaceFirstChar { it.uppercase() }, fontWeight = FontWeight.SemiBold)
                IconButton(onClick = { if (monthOffset > 0) monthOffset-- }, enabled = monthOffset > 0) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Mes siguiente")
                }
            }
        }
        item {
            Row(
                Modifier.fillMaxWidth().background(Brand.card, RoundedCornerShape(24.dp)).padding(20.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Donut(categories, totalSpent, Modifier.size(140.dp))
                Spacer(Modifier.width(20.dp))
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Gastaste", color = Brand.secondaryText)
                    Text(Fmt.money(totalSpent), fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
                    Text("Te entró", color = Brand.secondaryText)
                    Text(Fmt.money(income), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Brand.primaryDark)
                }
            }
        }
        if (categories.isEmpty() && !loading) {
            item { Text("Sin gastos este mes.", color = Brand.secondaryText) }
        }
        items(categories, key = { it.key }) { item ->
            val share = if (totalSpent.signum() > 0) item.total.toDouble() / totalSpent.toDouble() else 0.0
            PastelRow(item, share)
        }
    }
}

@Composable
private fun PastelRow(item: CategoryTotal, share: Double) {
    val tint = Color(CategoryDisplay.color(item.key))
    Box(Modifier.fillMaxWidth().background(tint.copy(alpha = 0.09f), RoundedCornerShape(14.dp))) {
        Box(
            Modifier
                .fillMaxWidth(share.coerceIn(0.08, 1.0).toFloat())
                .height(64.dp)
                .background(tint.copy(alpha = 0.14f), RoundedCornerShape(14.dp)),
        )
        Row(Modifier.fillMaxWidth().height(64.dp).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            CategoryIcon(CategoryDisplay.emoji(item.key), tint)
            Spacer(Modifier.width(12.dp))
            Text(item.key, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f), maxLines = 1)
            Text(
                "${item.count}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Brand.secondaryText,
                modifier = Modifier.background(Color(0x14000000), RoundedCornerShape(50)).padding(horizontal = 7.dp, vertical = 2.dp),
            )
            Spacer(Modifier.width(10.dp))
            Column(horizontalAlignment = Alignment.End) {
                Text(Fmt.money(item.total), fontWeight = FontWeight.SemiBold)
                Text(String.format(Locale.US, "%.1f%%", share * 100), fontSize = 11.sp, color = Brand.secondaryText)
            }
        }
    }
}

@Composable
private fun Donut(categories: List<CategoryTotal>, total: BigDecimal, modifier: Modifier) {
    Canvas(modifier) {
        val stroke = 26.dp.toPx()
        val arcSize = Size(size.width - stroke, size.height - stroke)
        val topLeft = androidx.compose.ui.geometry.Offset(stroke / 2, stroke / 2)
        if (total.signum() <= 0) {
            drawArc(Color(0xFFE4E9E7), 0f, 360f, false, topLeft, arcSize, style = Stroke(stroke))
            return@Canvas
        }
        var start = -90f
        categories.forEach { c ->
            val sweep = (c.total.toDouble() / total.toDouble() * 360).toFloat()
            drawArc(Color(CategoryDisplay.color(c.key)), start, (sweep - 1.5f).coerceAtLeast(0.5f), false, topLeft, arcSize, style = Stroke(stroke))
            start += sweep
        }
    }
}

