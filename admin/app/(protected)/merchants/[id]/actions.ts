"use server";

import { requireAdminSession, assertUuid } from "@/lib/admin-session";
import { autoLocate, locateFromInput } from "@/lib/merchant-location";

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
  const { data: before } = await supabase.from("partner_merchants").select("maps_url").eq("id", merchantId).maybeSingle();
  const { error } = await supabase.from("partner_merchants").update(update).eq("id", merchantId);
  if (error) return { error: friendlyDbError(error) };
  // Enlace de Maps nuevo: se vuelve a sacar la ubicacion (avisos por cercania).
  const mapsChanged = (before as { maps_url: string | null } | null)?.maps_url !== parsed.fields.maps_url;
  await autoLocate("partner_merchants", merchantId, parsed.fields.maps_url, mapsChanged);

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
  /// 0085: dias para usarlo despues de desbloquearlo con cashback.
  unlock_valid_days: number;
  /// 0085: compra minima (US$) que ve el cajero; null = sin minimo.
  min_purchase: number | null;
  /// 0085: quien paga un bono en US$ (los de MonAvi se liquidan al comercio).
  funded_by: "comercio" | "monavi";
  /// 0085: fechas de la promocion (null = sin limite).
  available_from: string | null;
  available_until: string | null;
};

/// "2026-12-01" (input date) → inicio de ese dia en Panama (UTC-5).
function panamaDate(value: string, endOfDay: boolean): string | null | undefined {
  if (!value) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return undefined;
  return `${value}T${endOfDay ? "23:59:59" : "00:00:00"}-05:00`;
}

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

  const daysRaw = text(formData, "unlock_valid_days", 3) || "7";
  const unlockValidDays = /^\d{1,2}$/.test(daysRaw) ? Number(daysRaw) : NaN;
  if (!Number.isInteger(unlockValidDays) || unlockValidDays < 1 || unlockValidDays > 90) {
    return { error: "Los días para usarlo deben ser un número entero entre 1 y 90." };
  }

  const minRaw = text(formData, "min_purchase", 12);
  let minPurchase: number | null = null;
  if (minRaw) {
    minPurchase = /^\d{1,6}(\.\d{1,2})?$/.test(minRaw) ? Number(minRaw) : NaN;
    if (!(minPurchase > 0 && minPurchase <= 100_000)) {
      return { error: "La compra mínima debe ser un monto mayor que $0 con máximo 2 decimales, o dejarse vacía." };
    }
  }
  if (rewardType === "monto" && discountValue !== null && minPurchase !== null && minPurchase < discountValue) {
    return { error: "La compra mínima no puede ser menor que el valor del bono." };
  }

  const fundedBy = rewardType === "monto" && text(formData, "funded_by", 10) === "monavi" ? "monavi" : "comercio";

  const availableFrom = panamaDate(text(formData, "available_from", 10), false);
  const availableUntil = panamaDate(text(formData, "available_until", 10), true);
  if (availableFrom === undefined || availableUntil === undefined) {
    return { error: "Las fechas de la promoción no son válidas." };
  }
  if (availableFrom && availableUntil && availableUntil <= availableFrom) {
    return { error: "La fecha de fin debe ser después de la fecha de inicio." };
  }

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
      unlock_valid_days: unlockValidDays,
      min_purchase: minPurchase,
      funded_by: fundedBy,
      available_from: availableFrom,
      available_until: availableUntil,
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

// ---------------------------------------------------------------------------
// Sucursales (merchant_branches, migracion 0076): mas direcciones del mismo
// comercio (mismo RUC), cada una con su "Como llegar" y su PIN de caja.
// ---------------------------------------------------------------------------

function branchFields(formData: FormData): { error: string } | { name: string; address: string | null; maps_url: string | null } {
  const name = text(formData, "name", 80);
  if (name.length < 2) return { error: "Escribe el nombre de la sucursal (por ejemplo “Costa del Este”)." };
  const mapsUrl = optionalText(formData, "maps_url", 1000);
  if (mapsUrl && !/^https:\/\//i.test(mapsUrl)) return { error: "El enlace de Google Maps debe empezar con https://" };
  return { name, address: optionalText(formData, "address", 300), maps_url: mapsUrl };
}

export async function createBranch(merchantId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(merchantId);
  const fields = branchFields(formData);
  if ("error" in fields) return { error: fields.error };
  const supabase = supabaseAdmin();
  const { count } = await supabase
    .from("merchant_branches")
    .select("id", { count: "exact", head: true })
    .eq("merchant_id", merchantId);
  const { data: created, error } = await supabase
    .from("merchant_branches")
    .insert({ ...fields, merchant_id: merchantId, sort_order: count ?? 0 })
    .select("id")
    .single<{ id: string }>();
  if (error) return { error: error.message };
  if (created) await saveBranchLocation(created.id, formData, fields.maps_url, true);
  revalidateMerchant(merchantId);
  return { message: `Sucursal “${fields.name}” agregada. Si quieres saber qué canjes se hacen ahí, genérale su propio PIN.` };
}

export async function updateBranch(merchantId: string, branchId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(merchantId);
  assertUuid(branchId);
  const fields = branchFields(formData);
  if ("error" in fields) return { error: fields.error };
  const { data: before } = await supabaseAdmin().from("merchant_branches").select("maps_url").eq("id", branchId).maybeSingle();
  const { error } = await supabaseAdmin()
    .from("merchant_branches")
    .update({ ...fields, updated_at: new Date().toISOString() })
    .eq("id", branchId)
    .eq("merchant_id", merchantId);
  if (error) return { error: error.message };
  const mapsChanged = (before as { maps_url: string | null } | null)?.maps_url !== fields.maps_url;
  const located = await saveBranchLocation(branchId, formData, fields.maps_url, mapsChanged);
  revalidateMerchant(merchantId);
  return { message: located === "manual-error" ? "Sucursal guardada, pero no entendimos las coordenadas: pega algo como 9.0123, -79.5123." : "Sucursal guardada." };
}

export async function setBranchStatus(merchantId: string, branchId: string, status: "active" | "paused") {
  await requireAdminSession();
  assertUuid(merchantId);
  assertUuid(branchId);
  if (status !== "active" && status !== "paused") throw new Error("Estado inválido.");
  const { error } = await supabaseAdmin()
    .from("merchant_branches")
    .update({ status, updated_at: new Date().toISOString() })
    .eq("id", branchId)
    .eq("merchant_id", merchantId);
  if (error) throw new Error(error.message);
  revalidateMerchant(merchantId);
}

export async function deleteBranch(merchantId: string, branchId: string): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(merchantId);
  assertUuid(branchId);
  // Los canjes hechos ahi quedan (branch_id pasa a null: "principal").
  const { error } = await supabaseAdmin()
    .from("merchant_branches")
    .delete()
    .eq("id", branchId)
    .eq("merchant_id", merchantId);
  if (error) return { error: error.message };
  revalidateMerchant(merchantId);
  return { message: "Sucursal eliminada." };
}

/// PIN propio de la sucursal (igual que el del comercio: se muestra una vez).
export async function generateBranchPin(merchantId: string, branchId: string, _prev: RedeemPinState): Promise<RedeemPinState> {
  await requireAdminSession();
  assertUuid(merchantId);
  assertUuid(branchId);
  const supabase = supabaseAdmin();
  const { data: branch } = await supabase
    .from("merchant_branches")
    .select("id")
    .eq("id", branchId)
    .eq("merchant_id", merchantId)
    .maybeSingle<{ id: string }>();
  if (!branch) return { error: "La sucursal ya no existe." };
  const pin = String(randomInt(0, 1_000_000)).padStart(6, "0");
  const { error } = await supabase.rpc("set_branch_redeem_pin", { p_branch_id: branchId, p_pin: pin });
  if (error) return { error: `No se pudo guardar el PIN: ${error.message}` };
  revalidatePath(`/merchants/${merchantId}`);
  return { pin, generatedAt: Date.now() };
}

// ---------------------------------------------------------------------------
// Ubicacion para avisos por cercania (la app los usara en una version futura)
// ---------------------------------------------------------------------------

/// Coordenadas de una sucursal: las escritas a mano ganan; si no hay, se
/// sacan del enlace de Maps (si cambio o si todavia no tenia).
async function saveBranchLocation(
  branchId: string,
  formData: FormData,
  mapsUrl: string | null,
  mapsChanged: boolean
): Promise<"manual" | "manual-error" | "auto" | "none"> {
  const manual = optionalText(formData, "coordinates", 1000);
  if (manual) {
    const coords = await locateFromInput(manual);
    if (!coords) return "manual-error";
    await supabaseAdmin().from("merchant_branches").update(coords).eq("id", branchId);
    return "manual";
  }
  return (await autoLocate("merchant_branches", branchId, mapsUrl, mapsChanged)) ? "auto" : "none";
}

/// "Detectar del enlace de Maps" o pegar coordenadas / otro enlace.
export async function setMerchantLocation(merchantId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(merchantId);
  const supabase = supabaseAdmin();
  let input = optionalText(formData, "location", 1000);
  if (!input) {
    const { data } = await supabase.from("partner_merchants").select("maps_url").eq("id", merchantId).maybeSingle();
    input = (data as { maps_url: string | null } | null)?.maps_url ?? null;
    if (!input) return { error: "Este comercio no tiene enlace de Google Maps. Pega aquí el enlace o las coordenadas." };
  }
  const coords = await locateFromInput(input);
  if (!coords) {
    return {
      error:
        "No pudimos sacar la ubicación de ese enlace. En Google Maps, mantén presionado el punto del local, copia las coordenadas (por ejemplo 9.0123, -79.5123) y pégalas aquí.",
    };
  }
  const { error } = await supabase.from("partner_merchants").update(coords).eq("id", merchantId);
  if (error) return { error: error.message };
  revalidateMerchant(merchantId);
  revalidatePath("/cercania");
  return { message: `Ubicación guardada: ${coords.latitude}, ${coords.longitude}.` };
}

export async function setMerchantProximity(merchantId: string, enabled: boolean) {
  await requireAdminSession();
  assertUuid(merchantId);
  await supabaseAdmin().from("partner_merchants").update({ proximity_alerts: enabled }).eq("id", merchantId);
  revalidateMerchant(merchantId);
  revalidatePath("/cercania");
}
