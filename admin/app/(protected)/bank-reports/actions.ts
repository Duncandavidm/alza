"use server";

import { revalidatePath } from "next/cache";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { parseCsv } from "@/lib/csv";
import { callReconcileFunction } from "@/lib/edge-functions";

/// Columnas esperadas del CSV del banco: external_account_ref,
/// period_month (yyyy-MM-dd, cualquier dia del mes que se reporta —
/// reconcile-savings-reports lo toma tal cual, asi que debe ser el
/// primer dia del mes), avg_balance.
export async function uploadBankReport(formData: FormData): Promise<{ error?: string; inserted?: number }> {
  const bankPartnerId = String(formData.get("bank_partner_id") ?? "").trim();
  const file = formData.get("file") as File | null;
  if (!bankPartnerId || !file) return { error: "Falta el banco o el archivo." };

  const text = await file.text();
  const rows = parseCsv(text);
  if (rows.length === 0) return { error: "El CSV esta vacio o no se pudo leer." };

  const records = rows.map((row) => ({
    bank_partner_id: bankPartnerId,
    external_account_ref: row.external_account_ref,
    period_month: row.period_month,
    avg_balance: Number(row.avg_balance),
    source: "bank_report",
  }));

  const missing = records.find((r) => !r.external_account_ref || !r.period_month || !r.avg_balance);
  if (missing) {
    return { error: "Alguna fila le falta un campo requerido (external_account_ref, period_month, avg_balance)." };
  }

  const supabase = supabaseAdmin();
  const { error } = await supabase
    .from("savings_bank_reports")
    .upsert(records, { onConflict: "bank_partner_id,external_account_ref,period_month", ignoreDuplicates: true });
  if (error) return { error: error.message };

  revalidatePath("/bank-reports");
  return { inserted: records.length };
}

export async function runBankReconciliation(formData: FormData): Promise<{ error?: string; summary?: string }> {
  const bankPartnerId = String(formData.get("bank_partner_id") ?? "").trim();
  if (!bankPartnerId) return { error: "Elige un banco." };
  try {
    const result = await callReconcileFunction("reconcile-savings-reports", {
      provider: "bank_report",
      bank_partner_id: bankPartnerId,
    });
    if (!result.ok) {
      return { error: `La funcion respondio ${result.status}: ${JSON.stringify(result.data)}` };
    }
    revalidatePath("/bank-reports");
    return { summary: JSON.stringify(result.data) };
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) };
  }
}
