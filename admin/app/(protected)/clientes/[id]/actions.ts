"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { requireAdminSession } from "@/lib/admin-session";
import { parseUuid } from "@/lib/push";
import { LIFETIME_PRODUCT_ID, SUSPEND_BAN_DURATION, canResetAccount, isProtectedEmail } from "@/lib/customer-accounts";

function back(id: string, key: "msg" | "err", text: string): never {
  redirect(`/clientes/${id}?${key}=${encodeURIComponent(text)}`);
}

async function loadUser(rawId: unknown) {
  await requireAdminSession();
  const id = parseUuid(rawId);
  if (!id) redirect(`/clientes?err=${encodeURIComponent("Cliente inválido.")}`);
  const { data, error } = await supabaseAdmin().auth.admin.getUserById(id);
  if (error || !data?.user) back(id, "err", `No se encontró la cuenta: ${error?.message ?? "no existe"}`);
  return { id, user: data.user };
}

/// Suspende (suspend=1) o reactiva (suspend=0) la cuenta. Un usuario con
/// ban no puede iniciar sesion ni renovar su sesion.
export async function setCustomerSuspended(formData: FormData) {
  await requireAdminSession();
  const { id, user } = await loadUser(formData.get("id"));
  const suspend = formData.get("suspend") === "1";
  if (isProtectedEmail(user.email)) {
    back(id, "err", "Esta es una cuenta protegida (demo / revisión de Apple): no se puede suspender ni eliminar desde el panel.");
  }
  const { error } = await supabaseAdmin().auth.admin.updateUserById(id, {
    ban_duration: suspend ? SUSPEND_BAN_DURATION : "none",
  });
  if (error) back(id, "err", `No se pudo ${suspend ? "suspender" : "reactivar"} la cuenta: ${error.message}`);
  revalidatePath("/clientes");
  revalidatePath(`/clientes/${id}`);
  back(id, "msg", suspend ? "Cuenta suspendida: ya no puede iniciar sesión." : "Cuenta reactivada.");
}

/// Reinicia la cuenta: borra movimientos, cuentas, metas, presupuestos,
/// facturas, cashback y canjes, y vuelve a pedir el onboarding. La cuenta,
/// el correo y la suscripcion se quedan. Exige escribir el correo.
export async function resetCustomer(formData: FormData) {
  await requireAdminSession();
  const { id, user } = await loadUser(formData.get("id"));
  if (!canResetAccount(user.email)) {
    back(id, "err", "La cuenta de revisión de Apple no se reinicia desde el panel.");
  }
  const typed = String(formData.get("confirm_email") ?? "").trim().toLowerCase();
  const real = (user.email ?? "").trim().toLowerCase();
  if (!real || typed !== real) back(id, "err", "El correo escrito no coincide con el de la cuenta. No se borró nada.");

  const { data, error } = await supabaseAdmin().rpc("admin_reset_account", { p_user_id: id });
  if (error) back(id, "err", `No se pudo reiniciar la cuenta: ${error.message}`);
  const deleted = Number((data as { transactions_deleted?: number } | null)?.transactions_deleted ?? 0);
  revalidatePath("/clientes");
  revalidatePath(`/clientes/${id}`);
  back(id, "msg", `Cuenta reiniciada (${deleted} movimientos borrados). La próxima vez que entre verá el onboarding.`);
}

/// Borra la cuenta para siempre. Exige que el admin escriba el correo
/// exacto; los datos de la app se borran por ON DELETE CASCADE.
export async function deleteCustomer(formData: FormData) {
  await requireAdminSession();
  const { id, user } = await loadUser(formData.get("id"));
  if (isProtectedEmail(user.email)) {
    back(id, "err", "Esta es una cuenta protegida (demo / revisión de Apple): no se puede suspender ni eliminar desde el panel.");
  }
  const typed = String(formData.get("confirm_email") ?? "").trim().toLowerCase();
  const real = (user.email ?? "").trim().toLowerCase();
  if (!real) back(id, "err", "La cuenta no tiene correo: no se puede confirmar el borrado desde el panel.");
  if (typed !== real) back(id, "err", "El correo escrito no coincide con el de la cuenta. No se borró nada.");

  const { error } = await supabaseAdmin().auth.admin.deleteUser(id);
  if (error) back(id, "err", `No se pudo eliminar la cuenta: ${error.message}`);
  revalidatePath("/clientes");
  redirect(`/clientes?msg=${encodeURIComponent(`Cuenta ${user.email} eliminada para siempre.`)}`);
}

/// Da (grant=1) o quita (grant=0) el acceso Pro de por vida.
export async function setLifetimeAccess(formData: FormData) {
  await requireAdminSession();
  const { id } = await loadUser(formData.get("id"));
  const grant = formData.get("grant") === "1";
  const supabase = supabaseAdmin();

  const { data: current } = await supabase
    .from("subscriptions")
    .select("product_id, status, apple_original_transaction_id")
    .eq("user_id", id)
    .maybeSingle();

  if (grant) {
    // Si ya paga por Apple, no se pisa su suscripcion (se perderia el
    // vinculo con Apple para renovaciones y reembolsos).
    if (current?.apple_original_transaction_id && current.status === "active") {
      back(id, "err", "Esta persona ya tiene una suscripción activa pagada por Apple. No se cambió nada.");
    }
    const { error } = await supabase.from("subscriptions").upsert({
      user_id: id,
      product_id: LIFETIME_PRODUCT_ID,
      status: "active",
      apple_transaction_id: null,
      apple_original_transaction_id: null,
      expires_at: null,
    });
    if (error) back(id, "err", `No se pudo dar el acceso: ${error.message}`);
  } else {
    if (current?.product_id !== LIFETIME_PRODUCT_ID) {
      back(id, "err", "Esta cuenta no tiene acceso de por vida otorgado desde el panel.");
    }
    const { error } = await supabase
      .from("subscriptions")
      .delete()
      .eq("user_id", id)
      .eq("product_id", LIFETIME_PRODUCT_ID);
    if (error) back(id, "err", `No se pudo quitar el acceso: ${error.message}`);
  }
  revalidatePath("/clientes");
  revalidatePath(`/clientes/${id}`);
  back(id, "msg", grant ? "Acceso Pro de por vida activado." : "Acceso Pro de por vida quitado.");
}
