"use server";

import { revalidatePath } from "next/cache";
import { requireAdminSession } from "@/lib/admin-session";
import { supabaseAdmin } from "@/lib/supabase-admin";

type Row = { id: string; user_id: string; document_path: string | null; status: string };

async function load(id: string): Promise<Row> {
  const { data, error } = await supabaseAdmin()
    .from("income_verifications")
    .select("id, user_id, document_path, status")
    .eq("id", id)
    .single<Row>();
  if (error || !data) throw new Error("Solicitud no encontrada");
  if (data.status !== "pendiente") throw new Error("Esta solicitud ya se revisó");
  return data;
}

/// El documento se borra al revisarlo: solo queda el monto aprobado.
async function deleteDocument(path: string | null) {
  if (!path) return;
  const { error } = await supabaseAdmin().storage.from("income-docs").remove([path]);
  if (error) console.error("income-docs remove", error.message);
}

export async function approveIncome(id: string, formData: FormData) {
  await requireAdminSession();
  const amount = Number(String(formData.get("amount") ?? "").replace(/,/g, ""));
  if (!Number.isFinite(amount) || amount <= 0) throw new Error("Escribe el ingreso mensual aprobado");
  const note = String(formData.get("note") ?? "").trim().slice(0, 500) || null;
  const row = await load(id);
  const until = new Date();
  until.setMonth(until.getMonth() + 6);
  const supabase = supabaseAdmin();
  const { error: profileError } = await supabase
    .from("profiles")
    .update({ verified_income: Math.round(amount * 100) / 100, verified_income_until: until.toISOString().slice(0, 10) })
    .eq("id", row.user_id);
  if (profileError) throw new Error(profileError.message);
  await deleteDocument(row.document_path);
  const { error } = await supabase
    .from("income_verifications")
    .update({ status: "aprobada", approved_amount: amount, note, document_path: null, reviewed_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/verificacion-ingresos");
}

export async function rejectIncome(id: string, formData: FormData) {
  await requireAdminSession();
  const note = String(formData.get("note") ?? "").trim().slice(0, 500) || "El documento no permite confirmar tus ingresos.";
  const row = await load(id);
  await deleteDocument(row.document_path);
  const { error } = await supabaseAdmin()
    .from("income_verifications")
    .update({ status: "rechazada", note, document_path: null, reviewed_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/verificacion-ingresos");
}
