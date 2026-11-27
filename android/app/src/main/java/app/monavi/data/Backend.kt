package app.monavi.data

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.serializer.KotlinXSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/** Mismo proyecto de Supabase que la app de iPhone (clave publicable). */
object Backend {
    const val URL = "https://jfhevxztsvnlsuwkwtmd.supabase.co"
    private const val PUBLISHABLE_KEY = "sb_publishable_Sc7czB2BxbUwbUyKCXvmRg_y32J1KQi"

    val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
        coerceInputValues = true
    }

    val client: SupabaseClient by lazy {
        createSupabaseClient(URL, PUBLISHABLE_KEY) {
            defaultSerializer = KotlinXSerializer(json)
            install(Auth)
            install(Postgrest)
            install(Functions)
        }
    }

    val userId: String? get() = client.auth.currentUserOrNull()?.id
    fun requireUser(): String = userId ?: error("Sin sesión")
}

/** Lecturas y escrituras de la app, igual que los repositorios de iPhone. */
object Repo {
    private val db get() = Backend.client

    // ---- Perfil

    suspend fun profile(): Profile? =
        db.from("profiles").select { filter { eq("id", Backend.requireUser()) } }.decodeSingleOrNull<Profile>()

    suspend fun completeOnboarding(fullName: String, country: String = "PA") {
        db.from("profiles").update(buildJsonObject {
            if (fullName.isNotBlank()) put("full_name", fullName.trim())
            put("country", country)
            put("has_variable_income", false)
            put("onboarding_completed_at", Instant.now().toString())
        }) { filter { eq("id", Backend.requireUser()) } }
    }

    suspend fun entitlement(): EntitlementRow? =
        db.postgrest.rpc("get_entitlement_status").decodeList<EntitlementRow>().firstOrNull()

    // ---- Cuentas

    suspend fun accounts(): List<Account> =
        db.from("accounts").select {
            filter { eq("user_id", Backend.requireUser()) }
            order("created_at", Order.ASCENDING)
        }.decodeList()

    suspend fun createAccount(name: String, type: AccountType, balance: BigDecimal, currency: String = "USD"): Account =
        db.from("accounts").insert(NewAccount(Backend.requireUser(), name.trim(), type.raw, balance, currency)) {
            select()
        }.decodeSingle()

    suspend fun renameAccount(id: String, name: String) {
        db.from("accounts").update(buildJsonObject { put("name", name.trim()) }) { filter { eq("id", id) } }
    }

    // ---- Movimientos

    private fun dayBounds(day: LocalDate, zone: ZoneId = ZoneId.systemDefault()): Pair<String, String> {
        val start = day.atStartOfDay(zone).toInstant()
        val end = day.plusDays(1).atStartOfDay(zone).toInstant()
        return start.toString() to end.toString()
    }

    suspend fun transactionsOn(day: LocalDate): List<FinanceTransaction> {
        val (from, to) = dayBounds(day)
        return db.from("transactions").select {
            filter {
                eq("user_id", Backend.requireUser())
                gte("occurred_at", from)
                lt("occurred_at", to)
            }
            order("occurred_at", Order.DESCENDING)
        }.decodeList()
    }

    suspend fun transactionsBetween(from: Instant, to: Instant, limit: Long = 2000): List<FinanceTransaction> =
        db.from("transactions").select {
            filter {
                eq("user_id", Backend.requireUser())
                gte("occurred_at", from.toString())
                lt("occurred_at", to.toString())
            }
            order("occurred_at", Order.DESCENDING)
            limit(limit)
        }.decodeList()

    suspend fun monthTransactions(month: ZonedDateTime = ZonedDateTime.now()): List<FinanceTransaction> {
        val start = month.toLocalDate().withDayOfMonth(1).atStartOfDay(month.zone)
        return transactionsBetween(start.toInstant(), start.plusMonths(1).toInstant())
    }

    suspend fun addTransaction(
        accountId: String,
        magnitude: BigDecimal,
        type: MovementType,
        category: String?,
        description: String?,
        occurredAt: Instant = Instant.now(),
    ): FinanceTransaction {
        val signed = type.signed(magnitude)
        val created = db.from("transactions").insert(
            NewTransaction(
                userId = Backend.requireUser(),
                accountId = accountId,
                amount = signed,
                movementType = type.raw,
                category = category,
                description = description?.trim()?.ifEmpty { null },
                occurredAt = occurredAt.toString(),
            )
        ) { select() }.decodeSingle<FinanceTransaction>()
        incrementBalance(accountId, signed)
        return created
    }

    /** Igual que iPhone: la cuenta no cambia; el saldo se corrige con la diferencia. */
    suspend fun updateTransaction(tx: FinanceTransaction, magnitude: BigDecimal, type: MovementType, category: String?, description: String?) {
        val newSigned = if (tx.isFromInvoice) tx.amount else type.signed(magnitude)
        db.from("transactions").update(buildJsonObject {
            put("amount", newSigned)
            put("movement_type", if (tx.isFromInvoice) tx.movementRaw else type.raw)
            put("category", category)
            put("description", description?.trim()?.ifEmpty { null })
        }) { filter { eq("id", tx.id) } }
        val delta = newSigned - tx.amount
        if (delta.signum() != 0) incrementBalance(tx.accountId, delta)
    }

    suspend fun deleteTransaction(tx: FinanceTransaction) {
        db.from("transactions").delete { filter { eq("id", tx.id) } }
        incrementBalance(tx.accountId, tx.amount.negate())
    }

    private suspend fun incrementBalance(accountId: String, delta: BigDecimal) {
        db.postgrest.rpc("increment_account_balance", buildJsonObject {
            put("p_account_id", accountId)
            put("p_delta", delta)
        })
    }

    // ---- Presupuestos

    suspend fun budgets(): List<Budget> =
        db.from("budgets").select {
            filter { eq("user_id", Backend.requireUser()) }
            order("created_at", Order.ASCENDING)
        }.decodeList()

    suspend fun addBudget(category: String, limit: BigDecimal, period: String = "monthly") {
        db.from("budgets").insert(NewBudget(Backend.requireUser(), category, period, limit))
    }

    suspend fun deleteBudget(id: String) {
        db.from("budgets").delete { filter { eq("id", id) } }
    }

    suspend fun budgetProgress(): List<BudgetProgress> {
        val budgets = budgets()
        if (budgets.isEmpty()) return emptyList()
        val now = ZonedDateTime.now()
        val monthStart = now.toLocalDate().withDayOfMonth(1).atStartOfDay(now.zone)
        val weekStart = now.toLocalDate().minusDays((now.dayOfWeek.value - 1).toLong()).atStartOfDay(now.zone)
        val txs = transactionsBetween(minOf(monthStart, weekStart).toInstant(), now.plusDays(1).toInstant())
            .filter { !it.movementType.isInflow }
        return budgets.map { budget ->
            val from = if (budget.period == "weekly") weekStart.toInstant() else monthStart.toInstant()
            val spent = txs.filter { it.category.equals(budget.category, ignoreCase = true) && !it.occurredAt.isBefore(from) }
                .fold(BigDecimal.ZERO) { acc, t -> acc + t.amount.abs() }
            BudgetProgress(budget, spent)
        }
    }

    // ---- Categorías propias

    suspend fun userCategories(): List<UserCategory> =
        db.from("user_categories").select { filter { eq("user_id", Backend.requireUser()) } }
            .decodeList<UserCategory>().also { CategoryDisplay.update(it) }

    // ---- Cuenta

    suspend fun deleteMyAccount() {
        db.functions.invoke("delete-account", body = buildJsonObject { put("userId", Backend.requireUser()) })
        db.auth.signOut()
    }
}
