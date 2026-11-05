"use client";

import { useActionState } from "react";
import { runBankReconciliation } from "./actions";

type BankPartner = { id: string; name: string };

const initialState: { error?: string; summary?: string } = {};

export default function RunBankReconciliationForm({ partners }: { partners: BankPartner[] }) {
  const [state, formAction, isPending] = useActionState(
    async (_prev: typeof initialState, formData: FormData) => runBankReconciliation(formData),
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
      <div className="field" style={{ alignSelf: "end" }}>
        <button type="submit" disabled={isPending}>
          {isPending ? "Procesando..." : "Procesar reportes pendientes"}
        </button>
      </div>
      {state.error && <p className="error" style={{ gridColumn: "1 / -1" }}>{state.error}</p>}
      {state.summary && <p className="success-text" style={{ gridColumn: "1 / -1" }}>{state.summary}</p>}
    </form>
  );
}
