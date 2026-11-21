import Link from "next/link";
import ActionForm from "@/components/ActionForm";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { setMerchantLocation, setMerchantProximity } from "./actions";

/// Ubicacion del local principal para los avisos por cercania ("Estás
/// cerca de ...: tienes 10% de descuento"). La app los usara en una
/// version futura; aqui se deja todo listo.
export default async function LocationCard({ merchantId, hasMapsUrl }: { merchantId: string; hasMapsUrl: boolean }) {
  const { data, error } = await supabaseAdmin()
    .from("partner_merchants")
    .select("latitude, longitude, proximity_alerts")
    .eq("id", merchantId)
    .maybeSingle<{ latitude: number | null; longitude: number | null; proximity_alerts: boolean }>();

  if (error) {
    return (
      <div className="card">
        <h3>Avisos por cercanía</h3>
        <p className="error" style={{ margin: 0 }}>
          Falta aplicar la migración 0080 (avisos por cercanía) en Supabase para guardar ubicaciones.
        </p>
      </div>
    );
  }

  const hasCoords = data?.latitude !== null && data?.latitude !== undefined && data?.longitude !== null;
  const coords = hasCoords ? `${data?.latitude}, ${data?.longitude}` : null;
  const enabled = data?.proximity_alerts ?? true;

  return (
    <div className="card">
      <h3>Avisos por cercanía</h3>
      <p className="text-dim">
        Cuando un cliente que tiene un descuento o cupón de este comercio pase a menos de 300 m, la app le avisará (cuando
        salga la versión que lo incluye). Ajustes generales en <Link href="/cercania">Avisos por cercanía</Link>.
      </p>
      <p>
        {coords ? (
          <>
            📍 Local principal ubicado: <code>{coords}</code> ·{" "}
            <a href={`https://www.google.com/maps?q=${coords}`} target="_blank" rel="noreferrer">
              comprobar en el mapa
            </a>
          </>
        ) : (
          <span className="error">Sin ubicación: no se le puede avisar a nadie cerca de este local.</span>
        )}
      </p>
      <ActionForm action={setMerchantLocation.bind(null, merchantId)} className="inline-actions" submitLabel={coords ? "Actualizar ubicación" : "Guardar ubicación"}>
        <input
          type="text"
          name="location"
          maxLength={1000}
          placeholder={hasMapsUrl ? "Vacío = sacarla del enlace de Maps de la ficha · o pega coordenadas / otro enlace" : "Pega el enlace de Google Maps o las coordenadas (9.0123, -79.5123)"}
          style={{ flex: "1 1 320px" }}
        />
      </ActionForm>
      <form action={setMerchantProximity.bind(null, merchantId, !enabled)} style={{ marginTop: 12 }}>
        <span className={`badge ${enabled ? "active" : "paused"}`} style={{ marginRight: 10 }}>
          {enabled ? "Avisos activados" : "Avisos apagados"}
        </span>
        <button type="submit" className="secondary">
          {enabled ? "Apagar avisos de este comercio" : "Activar avisos de este comercio"}
        </button>
      </form>
    </div>
  );
}
