import "server-only";
import { callAdminEdgeFunction } from "./edge";

type ReconcileFunctionName = "reconcile-card-transactions" | "reconcile-savings-reports" | "verify-dgi-receipt";

/// Llama a una de las Edge Functions operativas (ver supabase/functions)
/// con el mismo header `x-admin-secret` que ellas exigen — este panel es
/// exactamente el tipo de "job admin" para el que se diseñaron, nunca
/// las llama la app movil.
export async function callReconcileFunction(
  functionName: ReconcileFunctionName,
  body: Record<string, unknown>
): Promise<{ ok: boolean; status: number; data: unknown }> {
  return callAdminEdgeFunction(functionName, body);
}
