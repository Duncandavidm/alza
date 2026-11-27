package app.monavi.data

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/** Formato de dinero de Panamá (USD): $1,234.56. */
object Fmt {
    private val usd: NumberFormat = NumberFormat.getCurrencyInstance(Locale.US).apply {
        currency = Currency.getInstance("USD")
    }

    fun money(value: BigDecimal): String = usd.format(value.setScale(2, RoundingMode.HALF_UP))
    fun money(value: Double): String = usd.format(value)

    /** "52.30" escrito con coma o punto -> BigDecimal. */
    fun parseAmount(text: String): BigDecimal? =
        text.trim().replace(",", ".").takeIf { it.isNotEmpty() }?.toBigDecimalOrNull()?.takeIf { it.signum() > 0 }
}
