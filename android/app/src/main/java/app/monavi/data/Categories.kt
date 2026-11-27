package app.monavi.data

/**
 * Categorías fijas: el texto es lo que se guarda en `transactions.category`
 * y `budgets.category`, igual que en iPhone. No cambiar, solo agregar.
 */
enum class Category(val raw: String, val emoji: String, val hex: Long) {
    INCOME("Ingreso", "💰", 0xFF00A585),
    HOUSING("Vivienda", "🏠", 0xFF00A585),
    FOOD("Comida", "🍔", 0xFFF4A07A),
    GROCERIES("Supermercado", "🛒", 0xFFF2C14E),
    UTILITIES("Servicios", "💡", 0xFF4A90E2),
    TRANSPORT("Transporte", "🚗", 0xFFE85D75),
    SHOPPING("Compras", "🛍️", 0xFFB37FEB),
    CLOTHING("Ropa", "👕", 0xFF5BC0BE),
    GOING_OUT("Salir", "🍻", 0xFFFF8C42),
    ENTERTAINMENT("Entretenimiento", "🎬", 0xFFD65DB1),
    SUBSCRIPTIONS("Suscripciones", "📺", 0xFF7A86E8),
    HEALTH("Salud", "🩺", 0xFF2BB673),
    EDUCATION("Educación", "📚", 0xFF3D7EA6),
    PETS("Mascotas", "🐾", 0xFFC49A6C),
    GIFTS("Regalos", "🎁", 0xFFF28AB2),
    TRAVEL("Viajes", "✈️", 0xFF36B5D8),
    SAVINGS("Ahorro", "💵", 0xFF027A64),
    SUPPLIERS("Proveedores", "🏭", 0xFF8D6E63),
    TRANSFERS("Transferencias", "🔁", 0xFF5C7CFA),
    OTHER("Otro", "📦", 0xFF9AA5A1);

    companion object {
        fun from(raw: String?): Category? = entries.firstOrNull { it.raw.equals(raw?.trim(), ignoreCase = true) }

        /** Para gastos (sin Ingreso). */
        val expenses = entries.filter { it != INCOME }
        val incomes = listOf(INCOME, SAVINGS, TRANSFERS, OTHER)
    }
}

/** Emoji y color para cualquier categoría guardada (fija o propia). */
object CategoryDisplay {
    @Volatile private var custom: Map<String, UserCategory> = emptyMap()

    fun update(list: List<UserCategory>) {
        custom = list.associateBy { it.name.trim().lowercase() }
    }

    fun emoji(raw: String?): String =
        Category.from(raw)?.emoji ?: custom[raw?.trim()?.lowercase()]?.emoji ?: "🏷️"

    fun color(raw: String?): Long = Category.from(raw)?.hex ?: 0xFF00A585
}
