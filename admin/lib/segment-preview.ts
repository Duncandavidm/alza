import "server-only";
import { supabaseAdmin } from "./supabase-admin";
import { num } from "./format";
import type { Segment } from "./segments";

export type SegmentPreview = { people: number; with_push: number; consented_total: number };

/// Alcance de un segmento (RPC segment_preview, migracion 0040).
export async function fetchSegmentPreview(
  segment: Segment
): Promise<{ preview: SegmentPreview | null; error: string | null }> {
  try {
    const { data, error } = await supabaseAdmin().rpc("segment_preview", { p_segment: segment });
    if (error) return { preview: null, error: error.message };
    const raw = (data ?? {}) as Record<string, unknown>;
    return {
      preview: { people: num(raw.people), with_push: num(raw.with_push), consented_total: num(raw.consented_total) },
      error: null,
    };
  } catch (error) {
    return { preview: null, error: error instanceof Error ? error.message : String(error) };
  }
}

/// Comercios para el selector "compró en este comercio".
export async function fetchSegmentMerchants(): Promise<{ name: string; ruc: string }[]> {
  const { data } = await supabaseAdmin()
    .from("partner_merchants")
    .select("name, ruc")
    .order("name")
    .returns<{ name: string; ruc: string | null }[]>();
  return (data ?? []).filter((row): row is { name: string; ruc: string } => Boolean(row.ruc));
}
