"use client";

import { useActionState } from "react";
import { uploadCardReport } from "./actions";

type Merchant = { id: string; name: string; ruc: string };

const initialState: { error?: string; inserted?: number } = {};

export default function UploadCardReportForm({ merchants }: { merchants: Merchant[] }) {
  const [state, formAction, isPending] = useActionState(
    async (_prev: typeof initialState, formData: FormData) => uploadCardReport(formData),
    initialState
  );

  return (
    <form action={formAction} className="grid-form">
      <div className="field">
        <label>Comercio</label>
        <select name="merchant_ruc" required>
          {merchants.map((merchant) => (
            <option key={merchant.id} value={merchant.ruc}>
              {merchant.name}
            </option>
          ))}
        </select>
      </div>
      <div className="field">
        <label>Archivo CSV</label>
        <input type="file" name="file" accept=".csv,text/csv" required />
      </div>
      <div className="field" style={{ alignSelf: "end" }}>
        <button type="submit" disabled={isPending}>
          {isPending ? "Subiendo..." : "Subir reporte"}
        </button>
      </div>
      {state.error && <p className="error" style={{ gridColumn: "1 / -1" }}>{state.error}</p>}
      {state.inserted !== undefined && (
        <p className="success-text" style={{ gridColumn: "1 / -1" }}>
          {state.inserted} fila(s) cargadas. Usa "Procesar reportes pendientes" para cruzarlas.
        </p>
      )}
    </form>
  );
}
