"use server";

import { revalidatePath } from "next/cache";
import { supabaseAdmin } from "@/lib/supabase-admin";

export async function createOffer(merchantId: string, formData: FormData) {
  const offerType = String(formData.get("offer_type") ?? "percent");
  const value = Number(formData.get("value"));
  const minAmountRaw = String(formData.get("min_amount") ?? "").trim();
  const budgetRaw = String(formData.get("budget_total_points") ?? "").trim();
  const endsAtRaw = String(formData.get("ends_at") ?? "").trim();

  if (!value || value <= 0) return;

  const supabase = supabaseAdmin();
  const { error } = await supabase.from("partner_merchant_offers").insert({
    merchant_id: merchantId,
    offer_type: offerType,
    value,
    min_amount: minAmountRaw ? Number(minAmountRaw) : null,
    budget_total_points: budgetRaw ? Number(budgetRaw) : null,
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
