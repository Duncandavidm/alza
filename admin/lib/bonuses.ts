// Bonos y regalos (tabla bonus_grants, migracion 0040).

import { parseDollarsToCents } from "./format";
import { parseUuid } from "./push";

export const BONUS_KINDS = ["cashback", "puntos", "cupon"] as const;
export type BonusKind = (typeof BONUS_KINDS)[number];

export const BONUS_KIND_LABELS: Record<BonusKind, string> = {
  cashback: "Cashback (US$)",
  puntos: "Puntos",
  cupon: "Producto gratis de un comercio",
};

export function toBonusKind(value: unknown): BonusKind {
  return (BONUS_KINDS as readonly unknown[]).includes(value) ? (value as BonusKind) : "cashback";
}

export type RewardOptionGroup = {
  merchant: string;
  items: { id: string; name: string; value: string }[];
};


export type BonusInput = {
  name: string;
  kind: BonusKind;
  amount: number | null;
  reward_item_id: string | null;
  message: string | null;
  expires_days: number;
  notify: boolean;
};

/// Valida los datos del bono (desde searchParams o FormData).
export function parseBonusInput(get: (key: string) => string | undefined | null): {
  input: BonusInput | null;
  error: string | null;
  raw: { name: string; kind: BonusKind; amount: string; points: string; rewardItemId: string; message: string; expiresDays: string; notify: boolean };
} {
  const read = (key: string) => String(get(key) ?? "");
  const raw = {
    name: read("name").replace(/\s+/g, " ").trim().slice(0, 80),
    kind: toBonusKind(read("kind")),
    amount: read("amount").trim().slice(0, 12),
    points: read("points").trim().slice(0, 9),
    rewardItemId: read("reward_item_id").trim(),
    message: read("message").replace(/\s+/g, " ").trim().slice(0, 240),
    expiresDays: read("expires_days").trim() || "30",
    // Casilla en un formulario GET: sin notify_set es la primera carga (por defecto si).
    notify: read("notify_set") === "1" ? read("notify") === "1" : true,
  };

  const fail = (error: string) => ({ input: null, error, raw });
  if (!raw.name) return fail("Ponle un nombre al bono (solo lo ves tú).");

  let amount: number | null = null;
  let rewardItemId: string | null = null;
  let expiresDays = 30;
  if (raw.kind === "cashback") {
    amount = parseDollarsToCents(raw.amount);
    if (!amount) return fail("Escribe el monto de cashback en dólares, por ejemplo 1.00.");
    if (amount > 10000) return fail("El cashback por persona no puede pasar de $100.00.");
  } else if (raw.kind === "puntos") {
    const points = Number(raw.points);
    if (!Number.isInteger(points) || points <= 0) return fail("Escribe cuántos puntos regalar (número entero).");
    if (points > 100000) return fail("Son demasiados puntos por persona (máximo 100 000).");
    amount = points;
  } else {
    rewardItemId = parseUuid(raw.rewardItemId);
    if (!rewardItemId) return fail("Elige el producto que se regala.");
    expiresDays = Number(raw.expiresDays);
    if (!Number.isInteger(expiresDays) || expiresDays < 1 || expiresDays > 365) {
      return fail("El vencimiento debe estar entre 1 y 365 días.");
    }
  }

  return {
    input: {
      name: raw.name,
      kind: raw.kind,
      amount,
      reward_item_id: rewardItemId,
      message: raw.message || null,
      expires_days: expiresDays,
      notify: raw.notify,
    },
    error: null,
    raw,
  };
}

/// Campos del bono como hidden inputs para el paso de confirmacion.
export function bonusToFields(input: BonusInput): Record<string, string> {
  const fields: Record<string, string> = {
    name: input.name,
    kind: input.kind,
    message: input.message ?? "",
    notify_set: "1",
    notify: input.notify ? "1" : "0",
  };
  if (input.kind === "cashback" && input.amount) fields.amount = (input.amount / 100).toFixed(2);
  if (input.kind === "puntos" && input.amount) fields.points = String(input.amount);
  if (input.kind === "cupon" && input.reward_item_id) {
    fields.reward_item_id = input.reward_item_id;
    fields.expires_days = String(input.expires_days);
  }
  return fields;
}
