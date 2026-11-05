import "server-only";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// Cliente con la SERVICE ROLE KEY — nunca debe llegar al navegador. El
// `import "server-only"` hace que el build falle si este archivo se
// importa por error desde un componente cliente. Este panel necesita
// saltarse RLS a proposito: tablas como savings_bank_reports o las
// filas 'unmatched'/'ambiguous' de card_transactions no tienen ninguna
// policy para authenticated/anon (ver migraciones 0024 y 0027) — solo
// el panel admin (via service role) debe verlas.
let cachedClient: SupabaseClient | null = null;

export function supabaseAdmin(): SupabaseClient {
  if (cachedClient) return cachedClient;

  const url = process.env.SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) {
    throw new Error("Faltan las variables de entorno SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY");
  }

  cachedClient = createClient(url, serviceRoleKey, {
    auth: { persistSession: false },
  });
  return cachedClient;
}
