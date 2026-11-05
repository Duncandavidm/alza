"use server";

import { revalidatePath } from "next/cache";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { parseCsv } from "@/lib/csv";
import { callReconcileFunction } from "@/lib/edge-functions";

/// Columnas esperadas del CSV del comercio: provider_transaction_id,
/// occurred_at (ISO), amount, card_last4, card_brand (visa|mastercard|
/// amex|other), branch (opcional). report_status siempre 'settled' —
/// un reporte de ventas del comercio es de compras ya cobradas.
export async function uploadCardReport(formData: FormData): Promise<{ error?: string; inserted?: number }> {
  const merchantRuc = String(formData.get("merchant_ruc") ?? "").trim();
  const file = formData.get("file") as File | null;
  if (!merchantRuc || !file) return { error: "Falta el comercio o el archivo." };

  const text = await file.text();
  const rows = parseCsv(text);
  if (rows.length === 0) return { error: "El CSV esta vacio o no se pudo leer." };

  const records = rows.map((row) => ({
    provider: "merchant_report",
    provider_transaction_id: row.provider_transaction_id,
    merchant_ruc: merchantRuc,
    branch: row.branch || null,
    amount: Number(row.amount),
    occurred_at: row.occurred_at,
    card_last4: row.card_last4,
    card_brand: row.card_brand,
    report_status: "settled",
  }));

  const missing = records.find(
    (r) => !r.provider_transaction_id || !r.amount || !r.occurred_at || !r.card_last4 || !r.card_brand
  );
  if (missing) {
    return { error: "Alguna fila le falta un campo requerido (provider_transaction_id, amount, occurred_at, card_last4, card_brand)." };
  }

  const supabase = supabaseAdmin();
  const { error } = await supabase
    .from("card_transactions")
    .upsert(records, { onConflict: "provider,provider_transaction_id", ignoreDuplicates: true });
  if (error) return { error: error.message };

  revalidatePath("/card-reports");
  return { inserted: records.length };
}

export async function runCardReconciliation(): Promise<{ error?: string; summary?: string }> {
  try {
    const result = await callReconcileFunction("reconcile-card-transactions", { provider: "merchant_report" });
    if (!result.ok) {
      return { error: `La funcion respondio ${result.status}: ${JSON.stringify(result.data)}` };
    }
    revalidatePath("/card-reports");
    return { summary: JSON.stringify(result.data) };
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) };
  }
}
