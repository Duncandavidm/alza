import "server-only";
import { headers } from "next/headers";
import { supabaseAdmin } from "./supabase-admin";

// Limite de intentos para el inicio de sesion del panel (fuerza bruta):
// - 5 intentos fallidos en 15 minutos desde la misma IP la bloquean.
// - 30 intentos fallidos en 15 minutos en total (cualquier IP) bloquean
//   el inicio de sesion para todos durante ese rato.
const WINDOW_MINUTES = 15;
const MAX_FAILS_PER_IP = 5;
const MAX_FAILS_GLOBAL = 30;

export async function clientIp(): Promise<string> {
  const h = await headers();
  const forwarded = h.get("x-forwarded-for")?.split(",")[0]?.trim();
  return (forwarded || h.get("x-real-ip") || "desconocida").slice(0, 64);
}

export async function isLoginLocked(ip: string): Promise<boolean> {
  const since = new Date(Date.now() - WINDOW_MINUTES * 60_000).toISOString();
  const db = supabaseAdmin();
  const [{ count: ipFails }, { count: allFails }] = await Promise.all([
    db.from("admin_login_attempts").select("id", { count: "exact", head: true })
      .eq("ip", ip).eq("success", false).gte("created_at", since),
    db.from("admin_login_attempts").select("id", { count: "exact", head: true })
      .eq("success", false).gte("created_at", since),
  ]);
  return (ipFails ?? 0) >= MAX_FAILS_PER_IP || (allFails ?? 0) >= MAX_FAILS_GLOBAL;
}

export async function recordLoginAttempt(ip: string, success: boolean): Promise<void> {
  await supabaseAdmin().from("admin_login_attempts").insert({ ip, success });
}

export type AdminSecurity = {
  totp_secret: string | null;
  totp_pending_secret: string | null;
  totp_enabled: boolean;
  totp_last_step: number | null;
};

export async function getAdminSecurity(): Promise<AdminSecurity> {
  const { data, error } = await supabaseAdmin()
    .from("admin_security")
    .select("totp_secret, totp_pending_secret, totp_enabled, totp_last_step")
    .eq("id", 1)
    .maybeSingle();
  if (error) throw new Error(`No se pudo leer la seguridad del panel: ${error.message}`);
  return (data as AdminSecurity | null) ?? { totp_secret: null, totp_pending_secret: null, totp_enabled: false, totp_last_step: null };
}

export async function updateAdminSecurity(values: Partial<AdminSecurity>): Promise<void> {
  const { error } = await supabaseAdmin()
    .from("admin_security")
    .update({ ...values, updated_at: new Date().toISOString() })
    .eq("id", 1);
  if (error) throw new Error(`No se pudo guardar: ${error.message}`);
}
