// Notificaciones push segmentadas (tabla push_campaigns, migracion 0040).

export const PUSH_SCREENS = ["home", "points", "rewards", "redemptions"] as const;
export type PushScreen = (typeof PUSH_SCREENS)[number];

export const PUSH_SCREEN_LABELS: Record<PushScreen, string> = {
  home: "Inicio",
  points: "Puntos y cashback",
  rewards: "Premios (dónde canjear)",
  redemptions: "Mis canjes/regalos",
};

export const PUSH_STATUS_LABELS: Record<string, string> = {
  draft: "Sin enviar",
  sending: "Enviando",
  sent: "Enviada",
  failed: "Falló",
};

export const PUSH_TITLE_MAX = 80;
export const PUSH_BODY_MAX = 240;

export function toPushScreen(value: unknown): PushScreen {
  return (PUSH_SCREENS as readonly unknown[]).includes(value) ? (value as PushScreen) : "home";
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function parseUuid(value: unknown): string | null {
  const text = typeof value === "string" ? value.trim() : "";
  return UUID_RE.test(text) ? text.toLowerCase() : null;
}

export function cleanLine(value: unknown, max: number): string {
  return String(value ?? "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, max);
}
