"use server";

import { revalidatePath } from "next/cache";
import { requireAdminSession, assertUuid } from "@/lib/admin-session";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { parseDollarsToCents } from "@/lib/format";
import { optionalText, text } from "@/lib/validation";
import { toHabitRuleType } from "@/lib/habit-coupons";
import { fileFromForm, uploadRewardImage } from "@/lib/uploads";
import type { ActionState } from "@/components/ActionForm";

function intField(formData: FormData, key: string, min: number, max: number, fallback: number | null): number | null | undefined {
  const raw = text(formData, key, 9);
  if (!raw) return fallback;
  const value = Number(raw);
  return Number.isInteger(value) && value >= min && value <= max ? value : undefined;
}

/// Crea el cupon (reward_item de cupon, no sale en el catalogo) y su regla.
export async function createHabitCoupon(_prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  const merchantId = text(formData, "merchant_id", 40);
  if (!/^[0-9a-f-]{36}$/i.test(merchantId)) return { error: "Elige el comercio del cupón." };

  const cents = parseDollarsToCents(text(formData, "value", 12));
  if (cents === null || cents > 100_000) return { error: "El valor del cupón debe ser un monto en US$ (por ejemplo 20)." };
  const dollars = cents % 100 === 0 ? String(cents / 100) : (cents / 100).toFixed(2);
  const couponName = text(formData, "coupon_name", 120) || `Cupón de $${dollars}`;

  const ruleType = toHabitRuleType(text(formData, "rule_type", 30));
  const threshold = Number(text(formData, "threshold", 12) || "0");
  if (!Number.isFinite(threshold) || threshold < 0 || threshold > 100_000) return { error: "El mínimo de la regla no es válido." };
  if (ruleType === "ahorro_ingresos" && (threshold <= 0 || threshold > 100)) return { error: "El % de ahorro debe estar entre 1 y 100." };
  if (ruleType === "salud_financiera" && (threshold <= 0 || threshold > 100)) return { error: "El puntaje debe estar entre 1 y 100." };
  if (ruleType === "dias_registrados" && (threshold < 1 || threshold > 31)) return { error: "Los días deben estar entre 1 y 31." };

  const minLoggedDays = intField(formData, "min_logged_days", 0, 31, 15);
  if (minLoggedDays === undefined) return { error: "Los días mínimos anotados deben estar entre 0 y 31." };
  const maxCoupons = intField(formData, "max_coupons", 1, 1_000_000, null);
  if (maxCoupons === undefined) return { error: "El máximo de cupones debe ser un número entero, o déjalo vacío." };
  const expiresDays = intField(formData, "expires_days", 1, 365, 30);
  if (expiresDays === undefined) return { error: "Los días para usarlo deben estar entre 1 y 365." };

  const name = text(formData, "name", 120) || couponName;
  const supabase = supabaseAdmin();

  const insertItem: Record<string, unknown> = {
    merchant_id: merchantId,
    name: couponName,
    description: optionalText(formData, "conditions", 500),
    points_cost: cents,
    reward_type: "monto",
    discount_value: cents / 100,
    audience: "cupon",
    status: "active",
  };
  const photo = fileFromForm(formData, "photo");
  if (photo) {
    const upload = await uploadRewardImage(photo, "products", merchantId);
    if (upload.error) return { error: upload.error };
    insertItem.photo_url = upload.url;
  }
  const { data: item, error: itemError } = await supabase
    .from("reward_items")
    .insert(insertItem)
    .select("id")
    .single<{ id: string }>();
  if (itemError || !item) return { error: itemError?.message ?? "No se pudo crear el cupón." };

  const { error } = await supabase.from("habit_coupon_rules").insert({
    name,
    reward_item_id: item.id,
    rule_type: ruleType,
    threshold,
    min_logged_days: minLoggedDays,
    max_coupons: maxCoupons,
    expires_days: expiresDays,
    message: optionalText(formData, "message", 300),
  });
  if (error) {
    // Sin regla el cupon no sirve: se quita para no dejarlo suelto.
    await supabase.from("reward_items").delete().eq("id", item.id);
    return { error: error.message };
  }
  revalidatePath("/cupones");
  return { message: `Listo: “${couponName}” se entregará en la próxima corrida diaria (8:15 a. m.) a quien cumpla.` };
}

export async function setHabitCouponStatus(ruleId: string, status: "active" | "paused") {
  await requireAdminSession();
  assertUuid(ruleId);
  if (status !== "active" && status !== "paused") throw new Error("Estado inválido.");
  const { error } = await supabaseAdmin()
    .from("habit_coupon_rules")
    .update({ status, updated_at: new Date().toISOString() })
    .eq("id", ruleId);
  if (error) throw new Error(error.message);
  revalidatePath("/cupones");
}
