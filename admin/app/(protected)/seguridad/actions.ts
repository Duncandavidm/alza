"use server";

import { revalidatePath } from "next/cache";
import { requireAdminSession } from "@/lib/admin-session";
import { getAdminSecurity, updateAdminSecurity } from "@/lib/admin-login-guard";
import { generateTotpSecret, verifyTotp } from "@/lib/totp";

export type SecurityState = { error?: string; message?: string };

/// Genera una clave nueva (pendiente) para escanear con la app.
export async function startTotpSetup(): Promise<void> {
  await requireAdminSession();
  await updateAdminSecurity({ totp_pending_secret: generateTotpSecret() });
  revalidatePath("/seguridad");
}

/// Confirma la clave pendiente con un codigo de la app y la activa.
export async function confirmTotpSetup(_prev: SecurityState, formData: FormData): Promise<SecurityState> {
  await requireAdminSession();
  const code = String(formData.get("code") ?? "");
  const security = await getAdminSecurity();
  if (!security.totp_pending_secret) return { error: "Primero genera la clave." };
  const step = verifyTotp(security.totp_pending_secret, code, null);
  if (step === null) return { error: "Código incorrecto. Revisa que la hora del teléfono esté en automático." };
  await updateAdminSecurity({
    totp_secret: security.totp_pending_secret,
    totp_pending_secret: null,
    totp_enabled: true,
    totp_last_step: step,
  });
  revalidatePath("/seguridad");
  return { message: "Verificación en dos pasos activada. Desde ahora el inicio de sesión pide el código." };
}

/// Desactiva la verificacion en dos pasos (pide un codigo vigente).
export async function disableTotp(_prev: SecurityState, formData: FormData): Promise<SecurityState> {
  await requireAdminSession();
  const code = String(formData.get("code") ?? "");
  const security = await getAdminSecurity();
  if (!security.totp_enabled || !security.totp_secret) return { error: "No está activada." };
  const step = verifyTotp(security.totp_secret, code, security.totp_last_step);
  if (step === null) return { error: "Código incorrecto." };
  await updateAdminSecurity({ totp_secret: null, totp_pending_secret: null, totp_enabled: false, totp_last_step: null });
  revalidatePath("/seguridad");
  return { message: "Verificación en dos pasos desactivada." };
}
