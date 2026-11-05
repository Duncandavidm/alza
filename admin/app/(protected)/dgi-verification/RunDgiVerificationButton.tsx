"use client";

import { useActionState } from "react";
import { runDgiVerificationNow } from "./actions";

const initialState: { error?: string; summary?: string } = {};

export default function RunDgiVerificationButton() {
  const [state, formAction, isPending] = useActionState(
    async (_prev: typeof initialState) => runDgiVerificationNow(),
    initialState
  );

  return (
    <form action={formAction}>
      <button type="submit" disabled={isPending}>
        {isPending ? "Procesando..." : "Procesar ahora"}
      </button>
      {state.error && <p className="error">{state.error}</p>}
      {state.summary && <p className="success-text">{state.summary}</p>}
    </form>
  );
}
