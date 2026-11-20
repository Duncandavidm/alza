"use server";

import { requireAdminSession, assertUuid } from "@/lib/admin-session";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { CAMPAIGN_STATUSES, type CampaignStatus, friendlyCampaignDbError, parseCampaignFields } from "@/lib/campaigns";
import type { ActionState } from "@/components/ActionForm";

function revalidateCampaign(campaignId: string) {
  revalidatePath("/campaigns");
  revalidatePath(`/campaigns/${campaignId}`);
}

/// Crea la campaña en borrador: no aplica a ninguna factura hasta que se
/// activa desde su ficha.
export async function createCampaign(_prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  const parsed = parseCampaignFields(formData);
  if (!parsed.fields) return { error: parsed.error };

  const { data: created, error } = await supabaseAdmin()
    .from("brand_campaigns")
    .insert({ ...parsed.fields, status: "draft" })
    .select("id")
    .single<{ id: string }>();
  if (error || !created) return { error: error ? friendlyCampaignDbError(error) : "No se pudo crear la campaña." };

  revalidatePath("/campaigns");
  redirect(`/campaigns/${created.id}`);
}

export async function updateCampaign(campaignId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(campaignId);
  const parsed = parseCampaignFields(formData);
  if (!parsed.fields) return { error: parsed.error };

  const supabase = supabaseAdmin();
  const { data: current } = await supabase
    .from("brand_campaigns")
    .select("bonus_currency, budget_spent")
    .eq("id", campaignId)
    .maybeSingle<{ bonus_currency: string; budget_spent: number }>();
  if (!current) return { error: "No se encontró la campaña." };
  if (current.bonus_currency !== parsed.fields.bonus_currency && current.budget_spent > 0) {
    return { error: "La campaña ya entregó premios: no se puede cambiar la moneda del premio. Crea otra campaña." };
  }

  const { error } = await supabase
    .from("brand_campaigns")
    .update({ ...parsed.fields, updated_at: new Date().toISOString() })
    .eq("id", campaignId);
  if (error) return { error: friendlyCampaignDbError(error) };

  revalidateCampaign(campaignId);
  return { message: "Campaña guardada." };
}

/// Activar, pausar o terminar. Solo acepta estados validos.
export async function setCampaignStatus(campaignId: string, status: CampaignStatus) {
  await requireAdminSession();
  assertUuid(campaignId);
  if (!(CAMPAIGN_STATUSES as readonly string[]).includes(status) || status === "budget_exhausted") {
    throw new Error("Estado inválido.");
  }
  const { error } = await supabaseAdmin()
    .from("brand_campaigns")
    .update({ status, updated_at: new Date().toISOString() })
    .eq("id", campaignId);
  if (error) throw new Error(error.message);

  revalidateCampaign(campaignId);
}
