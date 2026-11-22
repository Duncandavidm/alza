// Cupones por buenos habitos (migracion 0068): tipos de regla y textos.
// Sin dependencias de servidor.

export type HabitRuleType =
  | "todos"
  | "ahorro_ingresos"
  | "meta_a_tiempo"
  | "presupuestos"
  | "dias_registrados"
  | "salud_financiera"
  | "semana_completa"
  | "facturas_mes";

export const HABIT_RULE_TYPES: { value: HabitRuleType; label: string; threshold: string; placeholder: string; help: string }[] = [
  {
    value: "todos",
    label: "Para todos (sin reglas)",
    threshold: "No aplica",
    placeholder: "",
    help: "Se le entrega una vez a cada cliente, también a los que se registren después, hasta el máximo de cupones que pongas. Ideal para promociones o para lanzar un aliado nuevo.",
  },
  {
    value: "ahorro_ingresos",
    label: "Ahorró un % de sus ingresos en el mes",
    threshold: "% mínimo de ahorro",
    placeholder: "20",
    help: "Ahorro = ingresos − gastos registrados del mes pasado. Se entrega desde el día 1 de cada mes.",
  },
  {
    value: "meta_a_tiempo",
    label: "Cumplió una meta de ahorro a tiempo",
    threshold: "Monto mínimo de la meta (US$)",
    placeholder: "100",
    help: "Llegó al monto de su meta antes de la fecha límite. La meta debe tener al menos 30 días. Uno por meta.",
  },
  {
    value: "presupuestos",
    label: "Cumplió todos sus presupuestos del mes",
    threshold: "Mínimo de presupuestos",
    placeholder: "2",
    help: "No se pasó en ninguno de sus presupuestos mensuales del mes pasado.",
  },
  {
    value: "dias_registrados",
    label: "Anotó sus movimientos muchos días del mes",
    threshold: "Días mínimos",
    placeholder: "20",
    help: "Días distintos con al menos un movimiento anotado en el mes pasado.",
  },
  {
    value: "semana_completa",
    label: "Anotó sus movimientos todos los días de la semana",
    threshold: "No aplica",
    placeholder: "",
    help: "Anotó al menos un movimiento cada día de la semana pasada (lunes a domingo). Se entrega cada lunes; una vez por semana.",
  },
  {
    value: "facturas_mes",
    label: "Escaneó X facturas en el mes",
    threshold: "Facturas confirmadas en el mes",
    placeholder: "15",
    help: "Meta mensual de facturas: en la app ven «Llevas 8 de 15 facturas este mes». Se entrega el día siguiente a llegar a la meta (solo cuentan las facturas que la DGI ya confirmó). Una vez por mes. No usa el mínimo de días anotados.",
  },
  {
    value: "salud_financiera",
    label: "Tuvo buena salud financiera en el mes",
    threshold: "Puntaje mínimo (0 a 100)",
    placeholder: "70",
    help: "Puntaje de 0 a 100: ahorro (40), presupuestos (20), constancia (20), facturas (10) y cuentas al día (10).",
  },
];

export function toHabitRuleType(value: unknown): HabitRuleType {
  return HABIT_RULE_TYPES.some((type) => type.value === value) ? (value as HabitRuleType) : "ahorro_ingresos";
}

export function habitRuleLabel(value: unknown): string {
  return HABIT_RULE_TYPES.find((type) => type.value === value)?.label ?? String(value);
}
