"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { friendlyDbError, parseMerchantFields } from "@/lib/merchant-form";
import { fileFromForm, uploadRewardImage, validateImage } from "@/lib/uploads";
import type { ActionState } from "@/components/ActionForm";

export async function createMerchant(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = parseMerchantFields(formData);
  if (!parsed.fields) return { error: parsed.error };

  const logo = fileFromForm(formData, "logo");
  if (logo) {
    const invalid = validateImage(logo);
    if (invalid) return { error: invalid };
  }

  const supabase = supabaseAdmin();
  const { data: created, error } = await supabase
    .from("partner_merchants")
    .insert(parsed.fields)
    .select("id")
    .single<{ id: string }>();
  if (error || !created) return { error: error ? friendlyDbError(error) : "No se pudo crear el comercio." };

  if (logo) {
    const upload = await uploadRewardImage(logo, "logos", created.id);
    if (upload.url) {
      await supabase.from("partner_merchants").update({ logo_url: upload.url }).eq("id", created.id);
    }
  }

  revalidatePath("/merchants");
  redirect(`/merchants/${created.id}`);
}

export async function updateMerchantStatus(merchantId: string, status: "active" | "paused") {
  const supabase = supabaseAdmin();
  const { error } = await supabase.from("partner_merchants").update({ status }).eq("id", merchantId);
  if (error) throw new Error(error.message);

  revalidatePath("/merchants");
  revalidatePath(`/merchants/${merchantId}`);
}
