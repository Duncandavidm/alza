// Categoria de un gasto a partir del comercio y del detalle de la factura.
// Los valores son los rawValue de TransactionCategory en la app.

export type Category =
  | "Supermercado" | "Comida" | "Salud" | "Transporte" | "Servicios" | "Compras"
  | "Ropa" | "Salir" | "Entretenimiento" | "Mascotas" | "Educación" | "Viajes"
  | "Suscripciones" | "Regalos" | "Otro";

function normalize(text: string): string {
  return text.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9 ]/g, " ");
}

function hasAny(text: string, words: string[]): boolean {
  return words.some((word) => new RegExp(`(^| )${word}`).test(text));
}

// Por nombre del comercio (lo mas confiable cuando existe).
const MERCHANT_RULES: [Category, string[]][] = [
  ["Supermercado", ["super", "supermercado", "riba smith", "el rey", "xtra", "machetazo", "el fuerte", "pricesmart", "mini super", "minisuper", "abarroteria"]],
  ["Salud", ["farmacia", "arrocha", "farmacias metro", "metro plus", "clinica", "hospital", "laboratorio", "optica", "dental"]],
  ["Transporte", ["gasolinera", "estacion", "terpel", "delta", "puma energy", "texaco", "shell", "accel", "taller", "autopartes", "panapass", "ena "]],
  ["Comida", ["restaurante", "cafe", "cafeteria", "panaderia", "pizza", "pizzeria", "mcdonald", "kfc", "burger", "subway", "fonda", "sushi", "pollo", "heladeria", "dunkin", "starbucks", "cocina", "grill", "bistro"]],
  ["Compras", ["do it", "novey", "cochez", "ferreteria", "multimax", "panafoto", "steren", "conway", "dollar", "tienda", "store", "mall"]],
  ["Ropa", ["zara", "h m", "stevens", "boutique", "calzado", "zapateria", "moda"]],
  ["Entretenimiento", ["cine", "cinepolis", "cinemark", "teatro", "bowling", "arena"]],
  ["Mascotas", ["veterinaria", "pet", "mascota"]],
  ["Servicios", ["ensa", "naturgy", "idaan", "cable onda", "tigo", "mas movil", "claro", "digicel"]],
  ["Educación", ["colegio", "universidad", "libreria", "escuela", "academia"]],
  ["Viajes", ["hotel", "copa airlines", "airlines", "hostal", "resort"]],
];

// Por descripcion de cada linea.
const ITEM_RULES: [Category, string[]][] = [
  ["Transporte", ["gasolina", "diesel", "combustible", "peaje", "estacionamiento", "parking", "aceite motor", "llanta", "lavado auto"]],
  ["Salud", ["acetaminofen", "ibuprofeno", "vitamina", "tableta", "tab ", "capsula", "jarabe", "mg ", "protector solar", "medicamento", "consulta", "antibiotico", "curita", "alcohol"]],
  ["Mascotas", ["perro", "gato", "canino", "felino", "mascota", "purina", "dog chow", "cat chow", "arena gato"]],
  ["Ropa", ["camisa", "pantalon", "blusa", "vestido", "zapato", "jeans", "falda", "short", "calcetin", "media ", "talla"]],
  ["Comida", ["combo", "hamburguesa", "pizza", "almuerzo", "desayuno", "cena", "capuchino", "latte", "espresso", "americano", "frappe", "sandwich", "emparedado", "empanada", "hojaldra", "sushi", "taco", "burrito", "helado", "croissant", "postre", "plato", "porcion", "orden de"]],
  ["Supermercado", ["arroz", "leche", "huevo", "pollo", "carne", "res ", "cerdo", "pescado", "salmon", "atun", "pan ", "queso", "yogurt", "cereal", "pasta", "aceite", "azucar", "sal ", "cafe molido", "frijol", "lenteja", "harina", "galleta", "salsa", "mantequilla", "jugo", "refresco", "agua", "soda", "banano", "manzana", "tomate", "cebolla", "papa", "platano", "fruta", "verdura", "detergente", "jabon", "papel higienico", "servilleta", "cloro", "suavizante", "pasta dental", "shampoo", "desodorante", "panal", "toalla"]],
  ["Compras", ["foco", "bombillo", "extension", "pintura", "cable", "herramienta", "tornillo", "bateria", "pila", "audifono", "cargador", "mueble"]],
  ["Entretenimiento", ["boleto", "entrada", "cine", "juego", "videojuego"]],
];

export function categoryForMerchant(name: string | null): Category | null {
  if (!name) return null;
  const text = ` ${normalize(name)} `;
  for (const [category, words] of MERCHANT_RULES) {
    if (words.some((word) => text.includes(` ${word}`) || text.includes(word))) return category;
  }
  return null;
}

export function categoryForItem(description: string): Category | null {
  const text = normalize(description) + " ";
  for (const [category, words] of ITEM_RULES) {
    if (hasAny(text, words)) return category;
  }
  return null;
}

export interface CategorizedLine {
  description: string;
  quantity: number | null;
  total: number | null;
  category: Category;
}

export interface Categorization {
  suggested: Category;
  lines: CategorizedLine[];
  breakdown: { category: Category; amount: number }[];
}

/// Cada linea toma su categoria por palabras; las que no se reconocen toman
/// la del comercio (o la que mas pesa). La sugerida para el gasto completo
/// es la del comercio si se conoce; si no, la de mayor monto.
export function categorize(
  merchantName: string | null,
  items: { description: string; quantity: number | null; total: number | null }[],
  invoiceTotal: number | null,
): Categorization {
  const merchantCategory = categoryForMerchant(merchantName);
  const guessed = items.map((item) => ({ ...item, category: categoryForItem(item.description) }));

  const totals = new Map<Category, number>();
  for (const line of guessed) {
    if (line.category) totals.set(line.category, (totals.get(line.category) ?? 0) + (line.total ?? 0));
  }
  const top = [...totals.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
  const fallback: Category = merchantCategory ?? top ?? "Compras";

  const lines: CategorizedLine[] = guessed.map((line) => ({ ...line, category: line.category ?? fallback }));

  const byCategory = new Map<Category, number>();
  for (const line of lines) byCategory.set(line.category, (byCategory.get(line.category) ?? 0) + (line.total ?? 0));

  // Ajusta al total pagado (impuestos/descuentos) repartiendo proporcional.
  const linesSum = [...byCategory.values()].reduce((sum, value) => sum + value, 0);
  const target = invoiceTotal ?? linesSum;
  let breakdown = [...byCategory.entries()]
    .map(([category, amount]) => ({ category, amount: linesSum > 0 ? (amount / linesSum) * target : 0 }))
    .sort((a, b) => b.amount - a.amount);
  breakdown = breakdown.map((entry) => ({ ...entry, amount: Math.round(entry.amount * 100) / 100 }));
  if (breakdown.length > 0) {
    const diff = Math.round((target - breakdown.reduce((sum, entry) => sum + entry.amount, 0)) * 100) / 100;
    breakdown[0].amount = Math.round((breakdown[0].amount + diff) * 100) / 100;
  } else if (target > 0) {
    breakdown = [{ category: fallback, amount: Math.round(target * 100) / 100 }];
  }

  return { suggested: merchantCategory ?? top ?? fallback, lines, breakdown };
}
