"use server";

import { randomInt } from "node:crypto";
import { revalidatePath } from "next/cache";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { friendlyDbError, parseMerchantFields } from "@/lib/merchant-form";
import { fileFromForm, uploadRewardImage } from "@/lib/uploads";
import { parseDollarsToCents } from "@/lib/format";
import { optionalText, text } from "@/lib/validation";
import type { ActionState } from "@/components/ActionForm";

function revalidateMerchant(merchantId: string) {
  revalidatePath("/merchants");
  revalidatePath(`/merchants/${merchantId}`);
}

// ---------------------------------------------------------------------------
// Ficha del comercio
// ---------------------------------------------------------------------------

export async function updateMerchant(merchantId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
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
  const { error } = await supabase.from("partner_merchants").update(update).eq("id", merchantId);
  if (error) return { error: friendlyDbError(error) };

  revalidateMerchant(merchantId);
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
};

function parseRewardItemFields(formData: FormData): { fields?: RewardItemFields; error?: string } {
  const name = text(formData, "name", 120);
  if (!name) return { error: "El nombre del producto es obligatorio." };

  // Se escribe en US$ (ej. 3.50) y se guarda en centavos (350): 1 punto = US$0.01.
  const pointsCost = parseDollarsToCents(text(formData, "cashback_value", 16));
  if (pointsCost === null || pointsCost > 10_000_000) {
    return { error: "El valor en cashback debe ser un monto mayor que $0 con máximo 2 decimales (por ejemplo 3.50)." };
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
    },
  };
}

export async function createRewardItem(merchantId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = parseRewardItemFields(formData);
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
  const parsed = parseRewardItemFields(formData);
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
  const supabase = supabaseAdmin();
  const { error } = await supabase.from("reward_items").update({ status }).eq("id", itemId).eq("merchant_id", merchantId);
  if (error) throw new Error(error.message);

  revalidateMerchant(merchantId);
}

export async function deleteRewardItem(merchantId: string, itemId: string): Promise<ActionState> {
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
