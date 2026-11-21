"use server";

import { revalidatePath } from "next/cache";
import { requireAdminSession, assertUuid } from "@/lib/admin-session";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { optionalText, text } from "@/lib/validation";
import type { ActionState } from "@/components/ActionForm";

function revalidateCategories() {
  revalidatePath("/categorias");
  revalidatePath("/merchants");
}

function parseOrder(formData: FormData): number | null {
  const raw = text(formData, "sort_order", 6);
  if (!raw) return 0;
  const value = Number(raw);
  return Number.isInteger(value) && value >= 0 && value <= 999 ? value : null;
}

export async function createCategory(_prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  const name = text(formData, "name", 60);
  if (name.length < 2) return { error: "Escribe el nombre de la categoría." };
  const sortOrder = parseOrder(formData);
  if (sortOrder === null) return { error: "El orden debe ser un número entre 0 y 999." };

  const { error } = await supabaseAdmin()
    .from("merchant_categories")
    .insert({ name, emoji: optionalText(formData, "emoji", 8), sort_order: sortOrder });
  if (error) {
    return { error: error.code === "23505" ? `Ya existe la categoría “${name}”.` : error.message };
  }
  revalidateCategories();
  return { message: `Categoría “${name}” creada.` };
}

export async function updateCategory(categoryId: string, _prev: ActionState, formData: FormData): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(categoryId);
  const name = text(formData, "name", 60);
  if (name.length < 2) return { error: "Escribe el nombre de la categoría." };
  const sortOrder = parseOrder(formData);
  if (sortOrder === null) return { error: "El orden debe ser un número entre 0 y 999." };

  const supabase = supabaseAdmin();
  const { data: before } = await supabase
    .from("merchant_categories").select("name").eq("id", categoryId).maybeSingle<{ name: string }>();
  if (!before) return { error: "La categoría ya no existe." };

  const { error } = await supabase
    .from("merchant_categories")
    .update({ name, emoji: optionalText(formData, "emoji", 8), sort_order: sortOrder })
    .eq("id", categoryId);
  if (error) return { error: error.code === "23505" ? `Ya existe la categoría “${name}”.` : error.message };

  // Los comercios guardan el nombre: si se renombra, se renombra en ellos.
  if (before.name !== name) {
    await supabase.from("partner_merchants").update({ category: name }).eq("category", before.name);
  }
  revalidateCategories();
  return { message: "Categoría guardada." };
}

export async function deleteCategory(categoryId: string): Promise<ActionState> {
  await requireAdminSession();
  assertUuid(categoryId);
  const supabase = supabaseAdmin();
  const { data: category } = await supabase
    .from("merchant_categories").select("name").eq("id", categoryId).maybeSingle<{ name: string }>();
  if (!category) return { error: "La categoría ya no existe." };
  const { count } = await supabase
    .from("partner_merchants").select("id", { count: "exact", head: true }).eq("category", category.name);
  if ((count ?? 0) > 0) {
    return { error: `No se puede borrar: ${count} comercio(s) la usan. Cámbiales la categoría primero.` };
  }
  const { error } = await supabase.from("merchant_categories").delete().eq("id", categoryId);
  if (error) return { error: error.message };
  revalidateCategories();
  return { message: `Categoría “${category.name}” eliminada.` };
}
