"use server";

import { revalidatePath } from "next/cache";
import { requireAdminSession, assertUuid } from "@/lib/admin-session";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { parseDollarsToCents } from "@/lib/format";
import { optionalText, text } from "@/lib/validation";
import { callIssueCoupons } from "@/lib/edge";
import type { ActionState } from "@/components/ActionForm";

function intField(formData: FormData, key: string, min: number, max: number, fallback: number | null): number | null | undefined {
  const raw = text(formData, key, 9);
  if (!raw) return fallback;
  const value = Number(raw);
  return Number.isInteger(value) && value >= min && value <= max ? value : undefined;
}

/// Fecha "AAAA-MM-DD" del formulario -> fin de ese dia en Panama (UTC-5).
function endOfPanamaDay(value: string): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const date = new Date(`${value}T23:59:59-05:00`);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

/// "Escanea 3 facturas de este comercio y gana un premio": crea el premio
/// (cupon que solo tiene quien gana el reto) y el reto.
export async function createMerchantChallenge(merchantId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(merchantId);
  const supabase = supabaseAdmin();

  const { data: merchant } = await supabase
    .from("partner_merchants")
    .select("name, ruc")
    .eq("id", merchantId)
    .maybeSingle<{ name: string; ruc: string | null }>();
  if (!merchant) return { error: "No se encontró el comercio." };
  if (!merchant.ruc) return { error: "Este comercio no tiene RUC en su ficha: sin RUC no se pueden contar sus facturas." };

  const required = intField(formData, "required_receipts", 1, 50, 3);
  if (!required) return { error: "Las facturas necesarias deben ser un número entre 1 y 50." };
  const maxWinners = intField(formData, "max_winners", 1, 1_000_000, null);
  if (maxWinners === undefined) return { error: "El máximo de ganadores debe ser un número entero, o déjalo vacío." };
  const expiresDays = intField(formData, "expires_days", 1, 365, 30);
  if (!expiresDays) return { error: "Los días para usar el premio deben estar entre 1 y 365." };

  const endsRaw = text(formData, "ends_on", 10);
  const endsAt = endsRaw ? endOfPanamaDay(endsRaw) : null;
  if (endsRaw && (!endsAt || new Date(endsAt) <= new Date())) return { error: "La fecha de fin debe ser una fecha futura." };

  const prize = text(formData, "prize", 120);
  if (prize.length < 3) return { error: "Escribe el premio (por ejemplo: Café gratis)." };
  const cents = parseDollarsToCents(text(formData, "value", 12) || "0");
  if (cents === null || cents > 100_000) return { error: "El valor del premio debe ser un monto en US$ (por ejemplo 3.50)." };

  const title = text(formData, "title", 120) || `Escanea ${required} facturas de ${merchant.name} y gana ${prize}`;

  const { data: item, error: itemError } = await supabase
    .from("reward_items")
    .insert({
      merchant_id: merchantId,
      name: prize,
      description: optionalText(formData, "conditions", 500),
      // Con valor: descuento de ese monto; sin valor: un producto gratis.
      points_cost: Math.max(cents, 1),
      reward_type: cents > 0 ? "monto" : "producto",
      discount_value: cents > 0 ? cents / 100 : null,
      audience: "cupon",
      status: "active",
    })
    .select("id")
    .single<{ id: string }>();
  if (itemError || !item) return { error: itemError?.message ?? "No se pudo crear el premio." };

  const { error } = await supabase.from("merchant_challenges").insert({
    merchant_id: merchantId,
    reward_item_id: item.id,
    title,
    required_receipts: required,
    ends_at: endsAt,
    max_winners: maxWinners,
    expires_days: expiresDays,
  });
  if (error) {
    await supabase.from("reward_items").delete().eq("id", item.id);
    return { error: error.message.includes("merchant_challenges") ? "Falta aplicar la migración 0083 en Supabase." : error.message };
  }

  await callIssueCoupons();
  revalidatePath(`/merchants/${merchantId}`);
  return { message: `Listo: reto “${title}” creado. Ya aparece en la app (1.0.5) con el avance de cada cliente; el premio se entrega solo, con aviso, al juntar las facturas confirmadas.` };
}

export async function setMerchantChallengeStatus(merchantId: string, challengeId: string, status: "active" | "paused") {
  await requireAdminSession();
  assertUuid(merchantId);
  assertUuid(challengeId);
  if (status !== "active" && status !== "paused") throw new Error("Estado inválido.");
  const { error } = await supabaseAdmin()
    .from("merchant_challenges")
    .update({ status, updated_at: new Date().toISOString() })
    .eq("id", challengeId)
    .eq("merchant_id", merchantId);
  if (error) throw new Error(error.message);
  if (status === "active") await callIssueCoupons();
  revalidatePath(`/merchants/${merchantId}`);
}
