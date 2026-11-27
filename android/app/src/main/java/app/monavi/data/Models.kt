package app.monavi.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import java.math.BigDecimal
import java.time.Instant

// Mismas tablas y columnas que la app de iPhone (Supabase).

/** numeric de Postgres <-> BigDecimal sin perder centavos. */
object BigDecimalSerializer : KSerializer<BigDecimal> {
    override val descriptor = PrimitiveSerialDescriptor("BigDecimal", PrimitiveKind.STRING)
    override fun deserialize(decoder: Decoder): BigDecimal =
        if (decoder is JsonDecoder) BigDecimal(decoder.decodeJsonElement().jsonPrimitive.content)
        else BigDecimal(decoder.decodeString())
    override fun serialize(encoder: Encoder, value: BigDecimal) {
        if (encoder is JsonEncoder) encoder.encodeJsonElement(JsonPrimitive(value)) else encoder.encodeString(value.toPlainString())
    }
}

object InstantSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("Instant", PrimitiveKind.STRING)
    override fun deserialize(decoder: Decoder): Instant = parseInstant(decoder.decodeString())
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(value.toString())
}

/** Postgres devuelve "2026-11-27T14:03:01.123+00:00" (a veces sin fracción). */
fun parseInstant(text: String): Instant =
    runCatching { Instant.parse(text) }.getOrElse { java.time.OffsetDateTime.parse(text).toInstant() }

typealias Money = @Serializable(with = BigDecimalSerializer::class) BigDecimal
typealias Timestamp = @Serializable(with = InstantSerializer::class) Instant

enum class MovementType(val raw: String, val label: String, val emoji: String) {
    INGRESO("ingreso", "Ingreso", "💰"),
    GASTO("gasto", "Gasto", "💸"),
    PAGO_PROVEEDOR("pago_proveedor", "Pago a proveedor", "🏭"),
    INVERSION("inversion", "Inversión", "📈"),
    TRANSFERENCIA("transferencia", "Transferencia", "💳");

    val isInflow get() = this == INGRESO
    fun signed(magnitude: BigDecimal): BigDecimal = if (isInflow) magnitude.abs() else magnitude.abs().negate()

    companion object {
        val quickAdd = listOf(INGRESO, GASTO, INVERSION)
        fun from(raw: String) = entries.firstOrNull { it.raw == raw } ?: GASTO
    }
}

enum class AccountType(val raw: String, val label: String) {
    CHECKING("checking", "Cuenta corriente"),
    SAVINGS("savings", "Ahorro"),
    CREDIT_CARD("credit_card", "Tarjeta de crédito"),
    INVESTMENT("investment", "Inversión"),
    CASH("cash", "Efectivo"),
    LOAN("loan", "Préstamo"),
    OTHER("other", "Otra");

    val isReserve get() = this == SAVINGS || this == INVESTMENT
    val isLiability get() = this == CREDIT_CARD || this == LOAN

    companion object {
        fun from(raw: String) = entries.firstOrNull { it.raw == raw } ?: OTHER
        val creatable = listOf(CHECKING, SAVINGS, CASH, CREDIT_CARD, INVESTMENT, OTHER)
    }
}

@Serializable
data class Account(
    val id: String,
    @SerialName("user_id") val userId: String,
    val name: String,
    @SerialName("type") val typeRaw: String,
    val balance: Money,
    val currency: String,
    @SerialName("created_at") val createdAt: Timestamp,
    @SerialName("debt_id") val debtId: String? = null,
    @SerialName("available_on") val availableOn: String? = null,
) {
    val type get() = AccountType.from(typeRaw)
}

@Serializable
data class NewAccount(
    @SerialName("user_id") val userId: String,
    val name: String,
    val type: String,
    val balance: Money,
    val currency: String,
)

@Serializable
data class FinanceTransaction(
    val id: String,
    @SerialName("user_id") val userId: String,
    @SerialName("account_id") val accountId: String,
    val amount: Money,
    @SerialName("movement_type") val movementRaw: String,
    val category: String? = null,
    val description: String? = null,
    val tags: List<String> = emptyList(),
    @SerialName("occurred_at") val occurredAt: Timestamp,
    @SerialName("created_at") val createdAt: Timestamp,
    @SerialName("invoice_cufe") val invoiceCufe: String? = null,
) {
    val movementType get() = MovementType.from(movementRaw)
    val isFromInvoice get() = invoiceCufe != null
}

@Serializable
data class NewTransaction(
    @SerialName("user_id") val userId: String,
    @SerialName("account_id") val accountId: String,
    val amount: Money,
    @SerialName("movement_type") val movementType: String,
    val category: String?,
    val description: String?,
    @SerialName("occurred_at") val occurredAt: String,
    val tags: List<String> = emptyList(),
)

@Serializable
data class Budget(
    val id: String,
    @SerialName("user_id") val userId: String,
    val category: String,
    val period: String,
    @SerialName("limit_amount") val limitAmount: Money,
    val color: String? = null,
)

@Serializable
data class NewBudget(
    @SerialName("user_id") val userId: String,
    val category: String,
    val period: String,
    @SerialName("limit_amount") val limitAmount: Money,
)

@Serializable
data class Profile(
    val id: String,
    @SerialName("full_name") val fullName: String? = null,
    @SerialName("onboarding_completed_at") val onboardingCompletedAt: String? = null,
    val country: String = "PA",
)

@Serializable
data class UserCategory(
    val id: String,
    @SerialName("user_id") val userId: String,
    val name: String,
    val emoji: String,
    val kind: String,
)

@Serializable
data class EntitlementRow(
    val status: String,
    @SerialName("product_id") val productId: String? = null,
    @SerialName("expires_at") val expiresAt: String? = null,
    @SerialName("is_trial") val isTrial: Boolean = false,
) {
    val isEntitled get() = status == "active" || status == "in_grace_period"
}

data class BudgetProgress(val budget: Budget, val spent: BigDecimal) {
    val ratio: Double
        get() = if (budget.limitAmount.signum() <= 0) 0.0 else spent.toDouble() / budget.limitAmount.toDouble()
    val status: Status get() = when {
        ratio >= 1.0 -> Status.OVER
        ratio >= 0.8 -> Status.WARNING
        else -> Status.ON_TRACK
    }
    enum class Status { ON_TRACK, WARNING, OVER }
}
