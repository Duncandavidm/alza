import Link from "next/link";
import ActionForm from "@/components/ActionForm";
import StatTile from "@/components/StatTile";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { fetchProximitySettings } from "@/lib/merchant-location";
import { locateAllMissing, updateProximitySettings } from "./actions";

export const dynamic = "force-dynamic";

type Place = {
  merchantId: string;
  merchant: string;
  label: string;
  hasMaps: boolean;
  coords: string | null;
  alerts: boolean;
  merchantActive: boolean;
};

/// Avisos por cercania: "Estás cerca de Café La Esquina: tienes 10% de
/// descuento". Aqui se deja listo todo lo del servidor (ubicaciones y
/// ajustes); los avisos los mostrara la app en una version futura.
export default async function ProximityPage() {
  const supabase = supabaseAdmin();
  const [settings, merchantsRes, branchesRes, eventsRes] = await Promise.all([
    fetchProximitySettings(),
    supabase
      .from("partner_merchants")
      .select("id, name, status, maps_url, latitude, longitude, proximity_alerts")
      .order("name")
      .returns<{ id: string; name: string; status: string; maps_url: string | null; latitude: number | null; longitude: number | null; proximity_alerts: boolean }[]>(),
    supabase
      .from("merchant_branches")
      .select("id, merchant_id, name, status, maps_url, latitude, longitude")
      .eq("status", "active")
      .order("sort_order")
      .returns<{ id: string; merchant_id: string; name: string; status: string; maps_url: string | null; latitude: number | null; longitude: number | null }[]>(),
    supabase.from("proximity_events").select("kind").gte("created_at", new Date(Date.now() - 30 * 86_400_000).toISOString()).limit(50000),
  ]);

  if (merchantsRes.error) {
    return (
      <>
        <h1>Avisos por cercanía</h1>
        <div className="card">
          <p className="error" style={{ margin: 0 }}>
            Falta aplicar la migración <code>0080_proximity_alerts.sql</code> en Supabase (SQL Editor). Detalle: {merchantsRes.error.message}
          </p>
        </div>
      </>
    );
  }

  const merchants = merchantsRes.data ?? [];
  const byId = new Map(merchants.map((m) => [m.id, m]));
  const places: Place[] = [];
  for (const m of merchants) {
    places.push({
      merchantId: m.id,
      merchant: m.name,
      label: "Principal",
      hasMaps: Boolean(m.maps_url),
      coords: m.latitude !== null && m.longitude !== null ? `${m.latitude}, ${m.longitude}` : null,
      alerts: m.proximity_alerts,
      merchantActive: m.status === "active",
    });
  }
  for (const b of branchesRes.data ?? []) {
    const m = byId.get(b.merchant_id);
    if (!m) continue;
    places.push({
      merchantId: m.id,
      merchant: m.name,
      label: b.name,
      hasMaps: Boolean(b.maps_url),
      coords: b.latitude !== null && b.longitude !== null ? `${b.latitude}, ${b.longitude}` : null,
      alerts: m.proximity_alerts,
      merchantActive: m.status === "active",
    });
  }
  places.sort((a, b) => a.merchant.localeCompare(b.merchant, "es") || (a.label === "Principal" ? -1 : 1));

  const activePlaces = places.filter((p) => p.merchantActive);
  const ready = activePlaces.filter((p) => p.coords && p.alerts).length;
  const missing = activePlaces.filter((p) => !p.coords).length;
  const autoFixable = places.filter((p) => !p.coords && p.hasMaps).length;
  const events = (eventsRes.data ?? []) as { kind: string }[];
  const shown = events.filter((e) => e.kind === "shown").length;
  const opened = events.filter((e) => e.kind === "opened").length;

  return (
    <>
      <h1>Avisos por cercanía</h1>
      <p className="text-dim">
        Cuando un cliente que ya tiene un descuento o cupón en un comercio pase cerca de uno de sus locales, la app le
        avisa: “☕ Estás cerca de Café La Esquina: tienes 10% de descuento”. La ubicación del cliente nunca sale de su
        iPhone; aquí solo se guarda dónde están los locales. <strong>Los avisos empiezan a llegar cuando salga la versión de
        la app que los incluye</strong>; mientras tanto, deja las ubicaciones listas.
      </p>

      <section className="tiles">
        <StatTile label="Locales listos para avisar" value={ready} icon="pin" hint={`de ${activePlaces.length} locales publicados`} />
        <StatTile label="Sin ubicación" value={missing} icon="alert" hint={autoFixable > 0 ? `${autoFixable} se pueden sacar del enlace de Maps` : "Ponlas en la ficha de cada comercio"} />
        <StatTile label="Avisos mostrados (30 días)" value={shown} icon="bell" hint="Cuando salga la app con avisos" />
        <StatTile label="Avisos abiertos (30 días)" value={opened} icon="check" hint={shown > 0 ? `${Math.round((opened / shown) * 100)}% de los mostrados` : "—"} />
      </section>

      <div className="card">
        <h3>Ajustes</h3>
        <ActionForm action={updateProximitySettings} className="grid-form" submitLabel="Guardar ajustes">
          <div className="field">
            <label>Radio de aviso (metros)</label>
            <input type="number" name="radius" min={100} max={2000} step={50} defaultValue={settings.radiusM} required />
          </div>
          <div className="field">
            <label>Días entre avisos del mismo comercio</label>
            <input type="number" name="cooldown" min={1} max={60} defaultValue={settings.cooldownDays} required />
          </div>
          <div className="field">
            <label>Máximo de avisos por día (por cliente)</label>
            <input type="number" name="daily_max" min={1} max={10} defaultValue={settings.dailyMax} required />
          </div>
          <div className="field">
            <label>Sin avisos desde las (hora, 0-23)</label>
            <input type="number" name="quiet_start" min={0} max={23} defaultValue={settings.quietStart} required />
          </div>
          <div className="field">
            <label>Hasta las (hora, 0-23)</label>
            <input type="number" name="quiet_end" min={0} max={23} defaultValue={settings.quietEnd} required />
          </div>
          <div className="field">
            <label>
              <input type="checkbox" name="enabled" defaultChecked={settings.enabled} /> Avisos por cercanía activados
            </label>
            <span className="text-dim">Solo se avisa a quien ya tiene un descuento o cupón en ese comercio.</span>
          </div>
        </ActionForm>
      </div>

      <div className="card">
        <div className="inline-actions" style={{ justifyContent: "space-between" }}>
          <h3 style={{ margin: 0 }}>Locales</h3>
          {autoFixable > 0 && (
            <ActionForm action={locateAllMissing} submitLabel={`Ubicar ${autoFixable} desde su enlace de Maps`} pendingLabel="Ubicando…" inline>
              {null}
            </ActionForm>
          )}
        </div>
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Comercio</th>
                <th>Local</th>
                <th>Ubicación</th>
                <th>Avisos</th>
              </tr>
            </thead>
            <tbody>
              {places.length === 0 && (
                <tr>
                  <td colSpan={4} className="text-dim">Todavía no hay comercios aliados.</td>
                </tr>
              )}
              {places.map((place, i) => (
                <tr key={`${place.merchantId}-${place.label}-${i}`} className={place.merchantActive ? undefined : "row-dim"}>
                  <td>
                    <Link href={`/merchants/${place.merchantId}`}>{place.merchant}</Link>
                    {!place.merchantActive && <div className="text-dim">Oculto (no sale en la app)</div>}
                  </td>
                  <td>{place.label}</td>
                  <td>
                    {place.coords ? (
                      <a href={`https://www.google.com/maps?q=${place.coords}`} target="_blank" rel="noreferrer">
                        📍 {place.coords}
                      </a>
                    ) : (
                      <span className="error">{place.hasMaps ? "Falta (se puede sacar del enlace)" : "Falta: sin enlace de Maps"}</span>
                    )}
                  </td>
                  <td>
                    <span className={`badge ${place.alerts ? "active" : "paused"}`}>{place.alerts ? "activados" : "apagados"}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="text-dim" style={{ marginTop: 10 }}>
          Para ubicar un local a mano o apagar los avisos de un comercio, entra a su ficha (tarjeta “Avisos por cercanía” y
          “Sucursales”).
        </p>
      </div>
    </>
  );
}
