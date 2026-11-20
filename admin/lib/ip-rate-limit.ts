import "server-only";
import { createHash } from "node:crypto";
import { headers } from "next/headers";
import { supabaseAdmin } from "./supabase-admin";

/// IP de quien envia la solicitud (Vercel pone la real en x-forwarded-for).
export async function requestIp(): Promise<string> {
  const h = await headers();
  return (h.get("x-forwarded-for")?.split(",")[0]?.trim() || h.get("x-real-ip") || "desconocida").slice(0, 64);
}

/// La IP como UUID estable (SHA-256) para usar el limite que ya existe en
/// la base (check_and_increment_rate_limit, migracion 0013).
function ipKey(ip: string): string {
  const x = createHash("sha256").update("ip:" + ip).digest("hex");
  return `${x.slice(0, 8)}-${x.slice(8, 12)}-4${x.slice(13, 16)}-8${x.slice(17, 20)}-${x.slice(20, 32)}`;
}

/// true si la IP todavia puede hacer la accion. Si la base no responde, NO
/// deja pasar (falla cerrado).
export async function allowIp(action: string, max: number, windowSeconds: number): Promise<boolean> {
  const { data, error } = await supabaseAdmin().rpc("check_and_increment_rate_limit", {
    p_user_id: ipKey(await requestIp()),
    p_function_name: `web:${action}`,
    p_max_requests: max,
    p_window_seconds: windowSeconds,
  });
  if (error) {
    console.error("allowIp", action, error.message);
    return false;
  }
  return data === true;
}
