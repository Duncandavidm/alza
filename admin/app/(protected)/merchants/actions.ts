"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";

export async function createMerchant(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  const ruc = String(formData.get("ruc") ?? "").trim();
  if (!name || !ruc) return;

  const supabase = supabaseAdmin();
  const { error } = await supabase.from("partner_merchants").insert({ name, ruc });
  if (error) throw new Error(error.message);

  revalidatePath("/merchants");
}

export async function updateMerchantStatus(merchantId: string, status: "active" | "paused") {
  const supabase = supabaseAdmin();
  const { error } = await supabase.from("partner_merchants").update({ status }).eq("id", merchantId);
  if (error) throw new Error(error.message);

  revalidatePath("/merchants");
  revalidatePath(`/merchants/${merchantId}`);
}
