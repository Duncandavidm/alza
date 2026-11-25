"use server";

import { revalidatePath } from "next/cache";
import { requireAdminSession } from "@/lib/admin-session";
import { supabaseAdmin } from "@/lib/supabase-admin";

export async function setColombiaEnabled(enabled: boolean) {
  await requireAdminSession();
  const { error } = await supabaseAdmin()
    .from("app_config")
    .upsert({ key: "colombia_enabled", value: enabled }, { onConflict: "key" });
  if (error) throw new Error(error.message);
  revalidatePath("/paises");
}
