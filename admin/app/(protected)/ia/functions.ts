// Funciones de IA (Edge Functions que llaman a Claude) con su nombre
// para el panel y el periodo por defecto de su cuota (app_config.ai_quotas).
export const AI_FUNCTIONS: { key: string; label: string; defaultLimit: number; defaultPeriod: "day" | "month" }[] = [
  { key: "parse-voice-transaction", label: "Notas por voz", defaultLimit: 300, defaultPeriod: "month" },
  { key: "ask-finances", label: "Pregúntale a tu dinero", defaultLimit: 100, defaultPeriod: "month" },
  { key: "generate-insights", label: "Insights", defaultLimit: 1, defaultPeriod: "day" },
  { key: "prioritize-payments", label: "Prioriza tus pagos", defaultLimit: 1, defaultPeriod: "day" },
];

export function aiFunctionLabel(key: string): string {
  return AI_FUNCTIONS.find((fn) => fn.key === key)?.label ?? key;
}
