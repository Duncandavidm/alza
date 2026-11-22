"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAdminSession, assertUuid } from "@/lib/admin-session";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { parseDollarsToCents } from "@/lib/format";
import { optionalText, text } from "@/lib/validation";
import { toHabitRuleType } from "@/lib/habit-coupons";
import { fileFromForm, uploadRewardImage } from "@/lib/uploads";
import { callIssueCoupons } from "@/lib/edge";
import type { ActionState } from "@/components/ActionForm";

function issuedText(result: { issued: number; pushes: number } | null): string {
  if (!result) return "Se entregará en la próxima corrida diaria (8:15 a. m.) a quien cumpla.";
  if (result.issued === 0) return "Por ahora nadie cumple la regla: se entregará solo, con aviso, a quien cumpla (se revisa cada día a las 8:15 a. m.).";
  return `Ya se entregaron ${result.issued} cupones y les avisamos a ${result.pushes} personas por notificación. Quien cumpla después lo recibirá solo.`;
}

function intField(formData: FormData, key: string, min: number, max: number, fallback: number | null): number | null | undefined {
  const raw = text(formData, key, 9);
  if (!raw) return fallback;
  const value = Number(raw);
  return Number.isInteger(value) && value >= min && value <= max ? value : undefined;
}

/// Crea el cupon (reward_item con audience 'cupon': no sale en el catalogo
/// de la app; solo lo tiene quien lo gana o a quien se lo regalas).
async function insertCouponItem(formData: FormData): Promise<{ id: string; name: string } | { error: string }> {
  const merchantId = text(formData, "merchant_id", 40);
  if (!/^[0-9a-f-]{36}$/i.test(merchantId)) return { error: "Elige el comercio del cupón." };

  const cents = parseDollarsToCents(text(formData, "value", 12));
  if (cents === null || cents > 100_000) return { error: "El valor del cupón debe ser un monto en US$ (por ejemplo 20)." };
  const dollars = cents % 100 === 0 ? String(cents / 100) : (cents / 100).toFixed(2);
  const couponName = text(formData, "coupon_name", 120) || `Cupón de $${dollars}`;

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
  const { data: item, error } = await supabaseAdmin()
    .from("reward_items")
    .insert(insertItem)
    .select("id")
    .single<{ id: string }>();
  if (error || !item) return { error: error?.message ?? "No se pudo crear el cupón." };
  return { id: item.id, name: couponName };
}

/// "Regalar cupones": crea el cupon y vuelve al formulario con el ya elegido.
export async function createGiftCoupon(_prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  const created = await insertCouponItem(formData);
  if ("error" in created) return { error: created.error };
  revalidatePath("/cupones/regalar");
  redirect(`/cupones/regalar?reward_item_id=${created.id}&name=${encodeURIComponent(created.name)}#regalo`);
}

/// Crea el cupon y su regla de buenos habitos.
export async function createHabitCoupon(_prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();

  const ruleType = toHabitRuleType(text(formData, "rule_type", 30));
  const threshold = Number(text(formData, "threshold", 12) || "0");
  if (!Number.isFinite(threshold) || threshold < 0 || threshold > 100_000) return { error: "El mínimo de la regla no es válido." };
  if (ruleType === "ahorro_ingresos" && (threshold <= 0 || threshold > 100)) return { error: "El % de ahorro debe estar entre 1 y 100." };
  if (ruleType === "salud_financiera" && (threshold <= 0 || threshold > 100)) return { error: "El puntaje debe estar entre 1 y 100." };
  if (ruleType === "dias_registrados" && (threshold < 1 || threshold > 31)) return { error: "Los días deben estar entre 1 y 31." };
  if (ruleType === "facturas_mes" && (!Number.isInteger(threshold) || threshold < 1 || threshold > 200)) {
    return { error: "La meta de facturas debe ser un número entero entre 1 y 200." };
  }

  const minLoggedDays = intField(formData, "min_logged_days", 0, 31, 15);
  if (minLoggedDays === undefined) return { error: "Los días mínimos anotados deben estar entre 0 y 31." };
  const maxCoupons = intField(formData, "max_coupons", 1, 1_000_000, null);
  if (maxCoupons === undefined) return { error: "El máximo de cupones debe ser un número entero, o déjalo vacío." };
  const expiresDays = intField(formData, "expires_days", 1, 365, 30);
  if (expiresDays === undefined) return { error: "Los días para usarlo deben estar entre 1 y 365." };

  const supabase = supabaseAdmin();
  const created = await insertCouponItem(formData);
  if ("error" in created) return { error: created.error };
  const item = { id: created.id };
  const couponName = created.name;
  const name = text(formData, "name", 120) || couponName;

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
  const issued = await callIssueCoupons();
  revalidatePath("/cupones");
  return { message: `Listo: “${couponName}” creado. ${issuedText(issued)}` };
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
  // Al activarlo se entrega ya a quien cumpla (con su aviso).
  if (status === "active") await callIssueCoupons();
  revalidatePath("/cupones");
}
