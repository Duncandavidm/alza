import "server-only";
import type { SupabaseClient, User } from "@supabase/supabase-js";

/// Cuentas de demo / revision de Apple: nunca se suspenden ni se borran
/// desde el panel.
export const PROTECTED_CUSTOMER_EMAILS = ["apple-review@monavi.app", "hola@maday.app"];

export function isProtectedEmail(email: string | null | undefined): boolean {
  return Boolean(email) && PROTECTED_CUSTOMER_EMAILS.includes(email!.trim().toLowerCase());
}

/// ban_duration de ~100 anos: en la practica, suspension indefinida.
export const SUSPEND_BAN_DURATION = "876000h";

export function isBanned(bannedUntil: string | null | undefined, now = Date.now()): boolean {
  if (!bannedUntil) return false;
  const time = Date.parse(bannedUntil);
  return Number.isFinite(time) && time > now;
}

/// Mapa id -> banned_until para los ids pedidos. admin_customers no trae
/// el estado de suspension, asi que se lee de Auth (una pagina de hasta
/// 1000 usuarios; suficiente por ahora). Si falla, devuelve un mapa vacio
/// para no romper la lista.
export async function bannedUntilByIds(supabase: SupabaseClient, ids: string[]): Promise<Map<string, string>> {
  const result = new Map<string, string>();
  if (ids.length === 0) return result;
  const wanted = new Set(ids);
  const perPage = 1000;
  for (let page = 1; page <= 20 && wanted.size > 0; page++) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage });
    if (error || !data) break;
    for (const user of data.users as User[]) {
      if (!wanted.has(user.id)) continue;
      wanted.delete(user.id);
      if (user.banned_until) result.set(user.id, user.banned_until);
    }
    if (data.users.length < perPage) break;
  }
  return result;
}
