"use client";

import { startTransition, useActionState } from "react";
import CopyButton from "@/components/CopyButton";
import type { RedeemPinState } from "./actions";

const REDEEM_URL = "https://monavi.maday.app/canjear";

type Props = {
  action: (prev: RedeemPinState) => Promise<RedeemPinState>;
  merchantName: string;
  pinSetAtLabel: string | null;
};

function instructions(merchantName: string, pin: string): string {
  return `Hola, equipo de ${merchantName}:

Este es el PIN de canje de MonAvi para su caja: ${pin}

Cómo validar un canje (desde cualquier celular o computadora, sin instalar nada):
1. Abran ${REDEEM_URL}
2. Escriban el código de 6 letras y números que el cliente les muestra en la app MonAvi, o escaneen su QR con la cámara del celular (se abre la página con el código ya escrito).
3. Escriban el PIN y toquen “Verificar”: verán el producto, su valor en cashback y la fecha de vencimiento.
4. Toquen “Confirmar entrega” y entreguen el producto al cliente. Cada código se puede usar una sola vez.

Pueden marcar “Recordar el PIN en este dispositivo” para no escribirlo con cada cliente. Compartan el PIN solo con quienes atienden la caja. Si se pierde o se filtra, escríbannos a hola@maday.app y les generamos uno nuevo (el anterior deja de funcionar).

¡Gracias por ser comercio aliado de MonAvi!`;
}

/// Genera el PIN de canje del comercio y lo muestra UNA sola vez (vive
/// solo en el estado de este componente; la base guarda el hash bcrypt).
export default function RedeemPinCard({ action, merchantName, pinSetAtLabel }: Props) {
  const [state, formAction, isPending] = useActionState(action, {});
  const hasPin = Boolean(pinSetAtLabel) || Boolean(state.pin);

  return (
    <div>
      <p>
        {hasPin ? (
          <>
            <span className="badge active">PIN activo</span>{" "}
            <span className="text-dim">
              {pinSetAtLabel ? `generado el ${pinSetAtLabel}` : "generado ahora"}
            </span>
          </>
        ) : (
          <>
            <span className="badge paused">sin PIN</span>{" "}
            <span className="text-dim">el comercio todavía no puede validar códigos en {REDEEM_URL}</span>
          </>
        )}
      </p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (
            hasPin &&
            !window.confirm(
              "¿Generar un PIN nuevo? El PIN actual dejará de funcionar de inmediato y habrá que enviarle el nuevo al comercio."
            )
          ) {
            return;
          }
          startTransition(() => formAction());
        }}
      >
        <button type="submit" disabled={isPending}>
          {isPending ? "Generando…" : "Generar PIN nuevo"}
        </button>
      </form>
      {state.error && <p className="error">{state.error}</p>}
      {state.pin && (
        <div className="pin-reveal" key={state.generatedAt}>
          <div className="text-dim">
            PIN nuevo de {merchantName}. Cópialo y envíaselo ahora: <strong>no se vuelve a mostrar</strong> (solo se guarda
            cifrado).
          </div>
          <div className="pin-value">{state.pin}</div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <CopyButton value={state.pin} label="Copiar PIN" />
            <CopyButton value={instructions(merchantName, state.pin)} label="Copiar instrucciones para el comercio" />
          </div>
          <pre className="pin-instructions">{instructions(merchantName, state.pin)}</pre>
        </div>
      )}
    </div>
  );
}
