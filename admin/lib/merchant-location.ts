import "server-only";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { parseCoordinates, resolveMapsLocation, type Coordinates } from "@/lib/geo";

/// Lo que se pega: coordenadas ("9.01, -79.52") o un enlace de Maps.
export async function locateFromInput(input: string): Promise<Coordinates | null> {
  const trimmed = input.trim();
  if (!trimmed) return null;
  return parseCoordinates(trimmed) ?? (await resolveMapsLocation(trimmed));
}

type Table = "partner_merchants" | "merchant_branches";

/// Al guardar un enlace de Maps nuevo (o si todavia no tiene ubicacion),
/// saca las coordenadas solas. Nunca hace fallar el guardado: si no se
/// pudo, el local queda "sin ubicación" y se completa a mano.
export async function autoLocate(table: Table, id: string, mapsUrl: string | null, force = false): Promise<boolean> {
  if (!mapsUrl) return false;
  const supabase = supabaseAdmin();
  if (!force) {
    const { data, error } = await supabase.from(table).select("latitude").eq("id", id).maybeSingle();
    if (error) return false; // falta la migracion 0080
    if (data && (data as { latitude: number | null }).latitude !== null) return false;
  }
  const coords = await resolveMapsLocation(mapsUrl);
  if (!coords) return false;
  const { error } = await supabase.from(table).update(coords).eq("id", id);
  return !error;
}

export type ProximitySettings = {
  enabled: boolean;
  radiusM: number;
  cooldownDays: number;
  dailyMax: number;
  quietStart: number;
  quietEnd: number;
};

export const DEFAULT_PROXIMITY: ProximitySettings = {
  enabled: true,
  radiusM: 300,
  cooldownDays: 7,
  dailyMax: 2,
  quietStart: 21,
  quietEnd: 8,
};

export async function fetchProximitySettings(): Promise<ProximitySettings> {
  const { data } = await supabaseAdmin()
    .from("app_config")
    .select("key, value")
    .like("key", "proximity_%");
  const map = new Map((data ?? []).map((row: { key: string; value: unknown }) => [row.key, row.value]));
  const n = (key: string, fallback: number) => {
    const value = Number(map.get(key));
    return Number.isFinite(value) ? value : fallback;
  };
  return {
    enabled: map.has("proximity_alerts_enabled") ? map.get("proximity_alerts_enabled") === true : DEFAULT_PROXIMITY.enabled,
    radiusM: n("proximity_radius_m", DEFAULT_PROXIMITY.radiusM),
    cooldownDays: n("proximity_cooldown_days", DEFAULT_PROXIMITY.cooldownDays),
    dailyMax: n("proximity_daily_max", DEFAULT_PROXIMITY.dailyMax),
    quietStart: n("proximity_quiet_start_hour", DEFAULT_PROXIMITY.quietStart),
    quietEnd: n("proximity_quiet_end_hour", DEFAULT_PROXIMITY.quietEnd),
  };
}
