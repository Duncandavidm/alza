import { formatInt } from "@/lib/format";
import type { SegmentPreview } from "@/lib/segment-preview";

/// Resultado de "Calcular alcance" (segment_preview).
export default function SegmentReach({ preview, error }: { preview: SegmentPreview | null; error: string | null }) {
  if (error) return <p className="error">No se pudo calcular el alcance: {error}</p>;
  if (!preview) return null;
  return (
    <div>
      <div className="kpi-grid">
        <div className="kpi">
          <div className="text-dim">Personas en el segmento</div>
          <div className="kpi-value">{formatInt(preview.people)}</div>
        </div>
        <div className="kpi">
          <div className="text-dim">Con notificaciones activas</div>
          <div className="kpi-value">{formatInt(preview.with_push)}</div>
        </div>
        <div className="kpi">
          <div className="text-dim">Total que aceptó ofertas</div>
          <div className="kpi-value">{formatInt(preview.consented_total)}</div>
        </div>
      </div>
      <ConsentNote />
    </div>
  );
}

export function ConsentNote() {
  return (
    <p className="text-dim" style={{ marginBottom: 0 }}>
      Solo se incluye a quienes aceptaron en la app recibir <strong>ofertas</strong>. Apple (regla 4.5.4) solo permite
      notificaciones promocionales con permiso explícito, así que el resto nunca entra en un segmento aunque cumpla los
      filtros.
    </p>
  );
}
