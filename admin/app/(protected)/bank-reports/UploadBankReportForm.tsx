"use client";

import { useActionState } from "react";
import { uploadBankReport } from "./actions";

type BankPartner = { id: string; name: string };

const initialState: { error?: string; inserted?: number } = {};

export default function UploadBankReportForm({ partners }: { partners: BankPartner[] }) {
  const [state, formAction, isPending] = useActionState(
    async (_prev: typeof initialState, formData: FormData) => uploadBankReport(formData),
    initialState
  );

  return (
    <form action={formAction} className="grid-form">
      <div className="field">
        <label>Banco</label>
        <select name="bank_partner_id" required>
          {partners.map((partner) => (
            <option key={partner.id} value={partner.id}>
              {partner.name}
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
