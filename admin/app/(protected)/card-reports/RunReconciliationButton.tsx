"use client";

import { useActionState } from "react";
import { runCardReconciliation } from "./actions";

const initialState: { error?: string; summary?: string } = {};

export default function RunReconciliationButton() {
  const [state, formAction, isPending] = useActionState(
    async (_prev: typeof initialState) => runCardReconciliation(),
    initialState
  );

  return (
    <form action={formAction}>
      <button type="submit" disabled={isPending}>
        {isPending ? "Procesando..." : "Procesar reportes pendientes"}
      </button>
      {state.error && <p className="error">{state.error}</p>}
      {state.summary && <p className="success-text">{state.summary}</p>}
    </form>
  );
}
