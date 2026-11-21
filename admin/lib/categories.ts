import "server-only";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { MERCHANT_CATEGORIES } from "@/lib/merchant-categories";

export type MerchantCategory = { id: string; name: string; emoji: string | null; sort_order: number };

/// Categorias de comercio que se administran en /categorias (migracion
/// 0068). Si la tabla no responde, cae en la lista fija de la landing.
export async function fetchMerchantCategories(): Promise<MerchantCategory[]> {
  const { data, error } = await supabaseAdmin()
    .from("merchant_categories")
    .select("id, name, emoji, sort_order")
    .order("sort_order", { ascending: true })
    .order("name", { ascending: true })
    .returns<MerchantCategory[]>();
  if (error || !data) {
    return MERCHANT_CATEGORIES.map((name, index) => ({ id: name, name, emoji: null, sort_order: index }));
  }
  return data;
}
