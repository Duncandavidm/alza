import "server-only";

type ReconcileFunctionName = "reconcile-card-transactions" | "reconcile-savings-reports";

/// Llama a una de las Edge Functions operativas (ver supabase/functions)
/// con el mismo header `x-admin-secret` que ellas exigen — este panel es
/// exactamente el tipo de "job admin" para el que se diseñaron, nunca
/// las llama la app movil.
export async function callReconcileFunction(
  functionName: ReconcileFunctionName,
  body: Record<string, unknown>
): Promise<{ ok: boolean; status: number; data: unknown }> {
  const url = process.env.SUPABASE_URL;
  const adminSecret = process.env.ADMIN_JOB_SECRET;
  if (!url || !adminSecret) {
    throw new Error("Faltan las variables de entorno SUPABASE_URL o ADMIN_JOB_SECRET");
  }

  const response = await fetch(`${url}/functions/v1/${functionName}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-admin-secret": adminSecret,
    },
    body: JSON.stringify(body),
  });

  const data = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, data };
}
