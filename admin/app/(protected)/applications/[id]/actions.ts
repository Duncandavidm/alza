"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { isApplicationStatus } from "@/lib/applications";
import { friendlyDbError } from "@/lib/merchant-form";
import { optionalText, parseMapsUrl, text } from "@/lib/validation";
import type { ActionState } from "@/components/ActionForm";

export async function updateApplication(applicationId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
  const status = text(formData, "status", 20);
  if (!isApplicationStatus(status)) return { error: "Estado inválido." };

  const { error } = await supabaseAdmin()
    .from("merchant_applications")
    .update({ status, notes: optionalText(formData, "notes", 4000) })
    .eq("id", applicationId);
  if (error) return { error: error.message };

  revalidatePath("/applications");
  revalidatePath(`/applications/${applicationId}`);
  return { message: "Cambios guardados." };
}

type ApplicationRow = {
  id: string;
  business_name: string;
  category: string | null;
  address: string | null;
  maps_url: string | null;
  merchant_id: string | null;
};

/// Crea el comercio aliado a partir de la solicitud (nombre, RUC,
/// categoria, direccion y Maps), la marca como 'aprobada' con el
/// merchant_id, y lleva al comercio para subir logo y productos.
export async function createMerchantFromApplication(
  applicationId: string,
  _prev: ActionState,
  formData: FormData
): Promise<ActionState> {
  const supabase = supabaseAdmin();
  const { data: application } = await supabase
    .from("merchant_applications")
    .select("id, business_name, category, address, maps_url, merchant_id")
    .eq("id", applicationId)
    .maybeSingle<ApplicationRow>();
  if (!application) return { error: "La solicitud ya no existe." };
  if (application.merchant_id) redirect(`/merchants/${application.merchant_id}`);

  const name = text(formData, "name", 120) || application.business_name;
  const ruc = text(formData, "ruc", 40);
  if (!ruc) return { error: "Escribe el RUC del comercio: es obligatorio para crear el comercio aliado." };

  const { data: existing } = await supabase
    .from("partner_merchants")
    .select("id, name")
    .eq("ruc", ruc)
    .maybeSingle<{ id: string; name: string }>();
  if (existing) {
    return { error: `Ya existe un comercio aliado con el RUC ${ruc} (${existing.name}). Revisa el RUC o abre ese comercio.` };
  }

  // Si el enlace de Maps que mandó el comercio no es válido, se crea igual
  // sin él (se puede corregir en la ficha).
  const maps = parseMapsUrl(application.maps_url ?? "");

  const { data: created, error } = await supabase
    .from("partner_merchants")
    .insert({
      name,
      ruc,
      category: application.category,
      address: application.address,
      maps_url: maps.error ? null : maps.url,
    })
    .select("id")
    .single<{ id: string }>();
  if (error || !created) return { error: error ? friendlyDbError(error) : "No se pudo crear el comercio." };

  const { error: linkError } = await supabase
    .from("merchant_applications")
    .update({ merchant_id: created.id, status: "aprobada", ruc })
    .eq("id", applicationId);
  if (linkError) return { error: `El comercio se creó, pero no se pudo actualizar la solicitud: ${linkError.message}` };

  revalidatePath("/applications");
  revalidatePath(`/applications/${applicationId}`);
  revalidatePath("/merchants");
  redirect(`/merchants/${created.id}`);
}
