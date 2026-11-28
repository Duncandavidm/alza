"use server";

import { revalidatePath } from "next/cache";
import { requireAdminSession } from "@/lib/admin-session";
import { supabaseAdmin } from "@/lib/supabase-admin";

/// Aprobar: el job diario libera lo que respalden los ingresos. Anular: el
/// cashback retenido de esa persona se anula.
export async function resolveReview(reviewId: string, approve: boolean, formData: FormData) {
  await requireAdminSession();
  const note = String(formData.get("note") ?? "").trim().slice(0, 500) || null;
  const { error } = await supabaseAdmin().rpc("resolve_cashback_review", {
    p_review_id: reviewId,
    p_approve: approve,
    p_note: note,
  });
  if (error) throw new Error(error.message);
  revalidatePath("/revision-cashback");
}
