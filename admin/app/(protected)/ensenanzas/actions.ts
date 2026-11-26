"use server";

import { revalidatePath } from "next/cache";
import { requireAdminSession } from "@/lib/admin-session";
import { supabaseAdmin } from "@/lib/supabase-admin";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function text(formData: FormData, key: string, max: number): string {
  return String(formData.get(key) ?? "").trim().slice(0, max);
}

function fields(formData: FormData) {
  const stepRaw = String(formData.get("step") ?? "");
  const step = /^[1-7]$/.test(stepRaw) ? Number(stepRaw) : null;
  const title = text(formData, "title", 120);
  const body = text(formData, "body", 1500);
  const aiNote = text(formData, "ai_note", 800);
  const source = text(formData, "source", 200);
  const countryRaw = String(formData.get("country") ?? "");
  const country = countryRaw === "PA" || countryRaw === "CO" ? countryRaw : null;
  const sort = Math.max(0, Math.min(10000, Math.round(Number(formData.get("sort") ?? 100)) || 100));
  if (title.length < 3) throw new Error("El título debe tener al menos 3 caracteres.");
  if (body.length < 10) throw new Error("La enseñanza debe tener al menos 10 caracteres.");
  return {
    country,
    step,
    title,
    body,
    ai_note: aiNote || null,
    source: source || null,
    sort,
    // La app no muestra lecciones: las enseñanzas son solo para la IA.
    show_in_app: false,
    use_in_ai: formData.get("use_in_ai") === "on",
  };
}

export async function createTeaching(formData: FormData) {
  await requireAdminSession();
  const { error } = await supabaseAdmin().from("finance_teachings").insert(fields(formData));
  if (error) throw new Error(error.message);
  revalidatePath("/ensenanzas");
}

export async function updateTeaching(formData: FormData) {
  await requireAdminSession();
  const id = String(formData.get("id") ?? "");
  if (!UUID_RE.test(id)) throw new Error("Enseñanza inválida.");
  const { error } = await supabaseAdmin().from("finance_teachings").update(fields(formData)).eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/ensenanzas");
}

export async function setTeachingActive(id: string, active: boolean) {
  await requireAdminSession();
  if (!UUID_RE.test(id)) throw new Error("Enseñanza inválida.");
  const { error } = await supabaseAdmin().from("finance_teachings").update({ active }).eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/ensenanzas");
}

export async function deleteTeaching(id: string) {
  await requireAdminSession();
  if (!UUID_RE.test(id)) throw new Error("Enseñanza inválida.");
  const { error } = await supabaseAdmin().from("finance_teachings").delete().eq("id", id);
  if (error) throw new Error(error.message);
  revalidatePath("/ensenanzas");
}
