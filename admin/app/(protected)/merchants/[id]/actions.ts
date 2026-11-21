"use server";

import { requireAdminSession, assertUuid } from "@/lib/admin-session";

import { randomInt } from "node:crypto";
import { revalidatePath } from "next/cache";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { friendlyDbError, parseMerchantFields } from "@/lib/merchant-form";
import { fileFromForm, uploadRewardImage } from "@/lib/uploads";
import { parseDollarsToCents } from "@/lib/format";
import { optionalText, text } from "@/lib/validation";
import { type RewardCurrency, toRewardCurrency } from "@/lib/currency";
import { type BenefitPeriod, type RewardType, defaultRewardName, toBenefitPeriod, toRewardType } from "@/lib/reward-type";
import type { ActionState } from "@/components/ActionForm";
import { callSendPush, describePushResult } from "@/lib/edge";
import { PUSH_BODY_MAX, PUSH_TITLE_MAX, cleanLine } from "@/lib/push";

function revalidateMerchant(merchantId: string) {
  revalidatePath("/merchants");
  revalidatePath(`/merchants/${merchantId}`);
}

// ---------------------------------------------------------------------------
// Ficha del comercio
// ---------------------------------------------------------------------------

export async function updateMerchant(merchantId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(merchantId);
  const parsed = parseMerchantFields(formData);
  if (!parsed.fields) return { error: parsed.error };

  const status = text(formData, "status", 10);
  const update: Record<string, unknown> = { ...parsed.fields };
  if (status === "active" || status === "paused") update.status = status;

  const logo = fileFromForm(formData, "logo");
  if (logo) {
    const upload = await uploadRewardImage(logo, "logos", merchantId);
    if (upload.error) return { error: upload.error };
    update.logo_url = upload.url;
  } else if (formData.get("remove_logo")) {
    update.logo_url = null;
  }

  const supabase = supabaseAdmin();
  const previousCurrency = await merchantCurrency(merchantId);
  const { error } = await supabase.from("partner_merchants").update(update).eq("id", merchantId);
  if (error) return { error: friendlyDbError(error) };

  revalidateMerchant(merchantId);
  if (previousCurrency && previousCurrency !== parsed.fields.reward_currency) {
    const { count } = await supabase
      .from("reward_items")
      .select("id", { count: "exact", head: true })
      .eq("merchant_id", merchantId);
    if ((count ?? 0) > 0) {
      return {
        message:
          "Ficha guardada. Cambiaste cómo canjean los clientes: revisa el valor de cada producto, no se convirtió automáticamente.",
      };
    }
  }
  return { message: "Ficha guardada." };
}

// ---------------------------------------------------------------------------
// PIN de canje en caja (/canjear)
// ---------------------------------------------------------------------------

export type RedeemPinState = { error?: string; pin?: string; generatedAt?: number };

/// Genera 6 digitos aleatorios (crypto.randomInt), los guarda SOLO como hash
/// bcrypt via set_merchant_redeem_pin y devuelve el PIN en claro una unica
/// vez para mostrarlo en pantalla. No se guarda en ningun otro lado: si se
/// pierde, se genera otro (y el anterior deja de funcionar).
export async function generateRedeemPin(merchantId: string, _prev: RedeemPinState): Promise<RedeemPinState> {
  await requireAdminSession();
  assertUuid(merchantId);
  const pin = String(randomInt(0, 1_000_000)).padStart(6, "0");
  const { error } = await supabaseAdmin().rpc("set_merchant_redeem_pin", {
    p_merchant_id: merchantId,
    p_pin: pin,
  });
  if (error) return { error: `No se pudo guardar el PIN: ${error.message}` };

  revalidatePath(`/merchants/${merchantId}`);
  return { pin, generatedAt: Date.now() };
}

// ---------------------------------------------------------------------------
// Ofertas de cashback (partner_merchant_offers). En la base siguen en
// puntos (1 punto = US$0.01): "percent" = puntos por dolar = % de cashback;
// "fixed" y el presupuesto se escriben en US$ y se guardan en centavos.
// ---------------------------------------------------------------------------

export async function createOffer(merchantId: string, formData: FormData) {
  await requireAdminSession();
  assertUuid(merchantId);
  const offerType = String(formData.get("offer_type") ?? "percent");
  const value = Number(formData.get("value"));
  const minAmountRaw = String(formData.get("min_amount") ?? "").trim();
  const budgetRaw = String(formData.get("budget_total_points") ?? "").trim();
  const endsAtRaw = String(formData.get("ends_at") ?? "").trim();

  if (!value || value <= 0) return;
  const storedValue = offerType === "fixed" ? Math.round(value * 100) : value;
  const budgetCents = budgetRaw ? parseDollarsToCents(budgetRaw) : null;
  if (budgetRaw && !budgetCents) return;

  const supabase = supabaseAdmin();
  const { error } = await supabase.from("partner_merchant_offers").insert({
    merchant_id: merchantId,
    offer_type: offerType,
    value: storedValue,
    min_amount: minAmountRaw ? Number(minAmountRaw) : null,
    budget_total_points: budgetCents,
    ends_at: endsAtRaw ? new Date(endsAtRaw).toISOString() : null,
  });
  if (error) throw new Error(error.message);

  revalidatePath(`/merchants/${merchantId}`);
}

export async function updateOfferStatus(merchantId: string, offerId: string, status: "active" | "paused") {
  await requireAdminSession();
  assertUuid(merchantId, offerId);
  if (status !== "active" && status !== "paused") throw new Error("Estado inválido.");
  const supabase = supabaseAdmin();
  const { error } = await supabase.from("partner_merchant_offers").update({ status }).eq("id", offerId);
  if (error) throw new Error(error.message);

  revalidatePath(`/merchants/${merchantId}`);
}

// ---------------------------------------------------------------------------
// Productos canjeables (reward_items)
// ---------------------------------------------------------------------------

type RewardItemFields = {
  name: string;
  description: string | null;
  points_cost: number;
  sort_order: number;
  status: "active" | "paused";
  reward_type: RewardType;
  discount_value: number | null;
  max_redemptions: number | null;
  /// Descuento gratis "por ser de MonAvi" (0067): no cuesta cashback.
  free_benefit: boolean;
  per_user_limit: number | null;
  per_user_period: BenefitPeriod | null;
};

/// Moneda de canje del comercio leida de la base (no se confia en el
/// formulario): decide como se interpreta el valor del producto.
async function merchantCurrency(merchantId: string): Promise<RewardCurrency | null> {
  const { data } = await supabaseAdmin()
    .from("partner_merchants")
    .select("reward_currency")
    .eq("id", merchantId)
    .maybeSingle<{ reward_currency: string | null }>();
  return data ? toRewardCurrency(data.reward_currency) : null;
}

function parseRewardItemFields(
  formData: FormData,
  currency: RewardCurrency
): { fields?: RewardItemFields; error?: string } {
  const rewardType = toRewardType(text(formData, "reward_type", 12));
  let discountValue: number | null = null;
  if (rewardType !== "producto") {
    const rawDiscount = text(formData, "discount_value", 12);
    discountValue = /^\d{1,6}(\.\d{1,2})?$/.test(rawDiscount) ? Number(rawDiscount) : NaN;
    if (rewardType === "porcentaje" && !(discountValue > 0 && discountValue <= 100)) {
      return { error: "El descuento debe ser un porcentaje entre 1 y 100 (por ejemplo 10)." };
    }
    if (rewardType === "monto" && !(discountValue > 0 && discountValue <= 100_000)) {
      return { error: "El cupón debe ser un monto mayor que $0 con máximo 2 decimales (por ejemplo 20)." };
    }
  }

  const name = text(formData, "name", 120) || defaultRewardName(rewardType, discountValue);
  if (!name) return { error: "El nombre del producto es obligatorio." };

  const maxRaw = text(formData, "max_redemptions", 9);
  let maxRedemptions: number | null = null;
  if (maxRaw) {
    maxRedemptions = /^\d{1,7}$/.test(maxRaw) ? Number(maxRaw) : NaN;
    if (!Number.isInteger(maxRedemptions) || maxRedemptions < 1 || maxRedemptions > 1_000_000) {
      return { error: "El límite de canjes debe ser un número entero mayor o igual a 1, o dejarse vacío para que no tenga límite." };
    }
  }

  const freeBenefit = text(formData, "access", 12) === "beneficio";
  let perUserLimit: number | null = null;
  let perUserPeriod: BenefitPeriod | null = null;
  if (freeBenefit) {
    const limitRaw = text(formData, "per_user_limit", 4) || "1";
    perUserLimit = /^\d{1,3}$/.test(limitRaw) ? Number(limitRaw) : NaN;
    if (!Number.isInteger(perUserLimit) || perUserLimit < 1 || perUserLimit > 100) {
      return { error: "Las veces por persona deben ser un número entero entre 1 y 100." };
    }
    perUserPeriod = toBenefitPeriod(text(formData, "per_user_period", 10));
  }

  const rawValue = text(formData, "reward_value", 16);
  let pointsCost: number | null;
  if (freeBenefit) {
    // Gratis: lo pone el comercio por traerle clientes, no cuesta cashback.
    pointsCost = 0;
  } else if (currency === "puntos") {
    // Puntos por buenos habitos: entero >= 1, se guarda tal cual.
    const points = /^\d{1,9}$/.test(rawValue) ? Number(rawValue) : NaN;
    if (!Number.isInteger(points) || points < 1 || points > 10_000_000) {
      return { error: "Los puntos necesarios deben ser un número entero mayor o igual a 1 (por ejemplo 150)." };
    }
    pointsCost = points;
  } else {
    // Se escribe en US$ (ej. 3.50) y se guarda en centavos (350): 1 punto = US$0.01.
    pointsCost = parseDollarsToCents(rawValue);
    if (pointsCost === null || pointsCost > 10_000_000) {
      return { error: "El valor en cashback debe ser un monto mayor que $0 con máximo 2 decimales (por ejemplo 3.50)." };
    }
  }

  const sortRaw = text(formData, "sort_order", 12);
  const sortOrder = sortRaw ? Number(sortRaw) : 0;
  if (!Number.isInteger(sortOrder)) return { error: "El orden debe ser un número entero." };

  const status = text(formData, "status", 10) === "paused" ? "paused" : "active";

  return {
    fields: {
      name,
      description: optionalText(formData, "description", 500),
      points_cost: pointsCost,
      sort_order: sortOrder,
      status,
      reward_type: rewardType,
      discount_value: discountValue,
      max_redemptions: maxRedemptions,
      free_benefit: freeBenefit,
      per_user_limit: perUserLimit,
      per_user_period: perUserPeriod,
    },
  };
}

export async function createRewardItem(merchantId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(merchantId);
  const currency = await merchantCurrency(merchantId);
  if (!currency) return { error: "No se encontró el comercio." };
  const parsed = parseRewardItemFields(formData, currency);
  if (!parsed.fields) return { error: parsed.error };

  const insert: Record<string, unknown> = { ...parsed.fields, merchant_id: merchantId };
  const photo = fileFromForm(formData, "photo");
  if (photo) {
    const upload = await uploadRewardImage(photo, "products", merchantId);
    if (upload.error) return { error: upload.error };
    insert.photo_url = upload.url;
  }

  const supabase = supabaseAdmin();
  const { error } = await supabase.from("reward_items").insert(insert);
  if (error) return { error: friendlyDbError(error) };

  revalidateMerchant(merchantId);
  return { message: `Producto “${parsed.fields.name}” agregado.` };
}

export async function updateRewardItem(
  merchantId: string,
  itemId: string,
  _prev: ActionState,
  formData: FormData
): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(merchantId, itemId);
  const currency = await merchantCurrency(merchantId);
  if (!currency) return { error: "No se encontró el comercio." };
  const parsed = parseRewardItemFields(formData, currency);
  if (!parsed.fields) return { error: parsed.error };

  const update: Record<string, unknown> = { ...parsed.fields };
  const photo = fileFromForm(formData, "photo");
  if (photo) {
    const upload = await uploadRewardImage(photo, "products", itemId);
    if (upload.error) return { error: upload.error };
    update.photo_url = upload.url;
  } else if (formData.get("remove_photo")) {
    update.photo_url = null;
  }

  const supabase = supabaseAdmin();
  const { error } = await supabase.from("reward_items").update(update).eq("id", itemId).eq("merchant_id", merchantId);
  if (error) return { error: friendlyDbError(error) };

  revalidateMerchant(merchantId);
  return { message: "Producto guardado." };
}

export async function setRewardItemStatus(merchantId: string, itemId: string, status: "active" | "paused") {
  await requireAdminSession();
  assertUuid(merchantId, itemId);
  if (status !== "active" && status !== "paused") throw new Error("Estado inválido.");
  const supabase = supabaseAdmin();
  const { error } = await supabase.from("reward_items").update({ status }).eq("id", itemId).eq("merchant_id", merchantId);
  if (error) throw new Error(error.message);

  revalidateMerchant(merchantId);
}

export async function deleteRewardItem(merchantId: string, itemId: string): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(merchantId, itemId);
  const supabase = supabaseAdmin();
  const { count } = await supabase
    .from("reward_redemptions")
    .select("id", { count: "exact", head: true })
    .eq("reward_item_id", itemId);
  if ((count ?? 0) > 0) {
    return { error: "No se puede borrar: este producto ya tiene canjes. Páusalo para ocultarlo de la app." };
  }

  const { error } = await supabase.from("reward_items").delete().eq("id", itemId).eq("merchant_id", merchantId);
  if (error) return { error: friendlyDbError(error) };

  revalidateMerchant(merchantId);
  return { message: "Producto eliminado." };
}

// ---------------------------------------------------------------------------
// Aviso personalizado del comercio (push con su logo)
// ---------------------------------------------------------------------------

/// Manda a quien acepto recibir ofertas un aviso de este comercio armado para
/// cada persona: su descuento gratis y cuanto cashback le falta para su
/// premio (o si ya le alcanza), con el logo del comercio como imagen. Si se
/// escribe un titulo, se usa ese y el mensaje va antes del texto personal.
export async function sendMerchantPush(merchantId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(merchantId);
  const supabase = supabaseAdmin();
  const { data: merchant } = await supabase
    .from("partner_merchants")
    .select("name, status")
    .eq("id", merchantId)
    .maybeSingle<{ name: string; status: string }>();
  if (!merchant) return { error: "No se encontró el comercio." };
  if (merchant.status !== "active") return { error: "Publica el comercio antes de avisar: todavía no sale en la app." };

  const customTitle = cleanLine(formData.get("title"), PUSH_TITLE_MAX);
  const customBody = cleanLine(formData.get("body"), PUSH_BODY_MAX);
  const { data: created, error } = await supabase
    .from("push_campaigns")
    .insert({
      title: customTitle || `Aviso de ${merchant.name}`.slice(0, 80),
      body: customBody || "Mensaje personalizado para cada persona (descuento y cashback que le falta).",
      screen: "rewards",
      segment: {},
      merchant_id: merchantId,
      custom_text: Boolean(customTitle),
      status: "draft",
    })
    .select("id")
    .single<{ id: string }>();
  if (error || !created) return { error: `No se pudo guardar el aviso: ${error?.message ?? "error desconocido"}` };

  const sent = await callSendPush({ push_campaign_id: created.id });
  revalidatePath("/notificaciones");
  if (!sent.ok) return { error: `Se guardó, pero no se pudo enviar: ${sent.error}. Reinténtalo desde Notificaciones.` };
  return { message: describePushResult(sent.result) };
}
