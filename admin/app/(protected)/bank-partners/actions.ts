"use server";

import { revalidatePath } from "next/cache";
import { supabaseAdmin } from "@/lib/supabase-admin";

export async function createBankPartner(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  if (!name) return;

  const supabase = supabaseAdmin();
  const { error } = await supabase.from("bank_partners").insert({ name });
  if (error) throw new Error(error.message);

  revalidatePath("/bank-partners");
}

export async function updateBankPartnerStatus(bankPartnerId: string, status: "active" | "paused") {
  const supabase = supabaseAdmin();
  const { error } = await supabase.from("bank_partners").update({ status }).eq("id", bankPartnerId);
  if (error) throw new Error(error.message);

  revalidatePath("/bank-partners");
}
