"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { redeemCode, type RedeemResult } from "./actions";

// El PIN se recuerda SOLO en este navegador (localStorage), para que el
// cajero no lo escriba con cada cliente. Se guarda despues de un PIN
// correcto y se puede olvidar con un toque.
const PIN_STORAGE_KEY = "monavi_redeem_pin";

type Verified = Extract<RedeemResult, { ok: true }>;
type Step = { kind: "form" } | { kind: "verified"; data: Verified } | { kind: "done"; data: Verified };

function readStoredPin(): string {
  try {
    const value = window.localStorage.getItem(PIN_STORAGE_KEY) ?? "";
    return /^\d{6}$/.test(value) ? value : "";
  } catch {
    return "";
  }
}

function storePin(pin: string | null) {
  try {
    if (pin) window.localStorage.setItem(PIN_STORAGE_KEY, pin);
    else window.localStorage.removeItem(PIN_STORAGE_KEY);
  } catch {
    // Modo privado o almacenamiento bloqueado: simplemente no se recuerda.
  }
}

const normalizeCode = (value: string) =>
  value
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 6);
const normalizePin = (value: string) => value.replace(/\D/g, "").slice(0, 6);

export default function RedeemForm({ initialCode }: { initialCode: string }) {
  const [code, setCode] = useState(initialCode);
  const [pin, setPin] = useState("");
  const [remember, setRemember] = useState(true);
  const [hasStoredPin, setHasStoredPin] = useState(false);
  const [step, setStep] = useState<Step>({ kind: "form" });
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const codeRef = useRef<HTMLInputElement>(null);
  const pinRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const stored = readStoredPin();
    if (stored) {
      setPin(stored);
      setHasStoredPin(true);
    }
    if (!initialCode) codeRef.current?.focus();
    else if (!stored) pinRef.current?.focus();
  }, [initialCode]);

  const canVerify = code.length === 6 && pin.length === 6 && !isPending;

  function run(confirm: boolean) {
    setError(null);
    startTransition(async () => {
      const result = await redeemCode({ code, pin, confirm });
      if (!result.ok) {
        setError(result.product ? `${result.error} (${result.product})` : result.error);
        if (confirm) setStep({ kind: "form" });
        return;
      }
      // PIN correcto: se recuerda (o se olvida) segun la casilla.
      storePin(remember ? pin : null);
      setHasStoredPin(remember);
      setStep(result.delivered ? { kind: "done", data: result } : { kind: "verified", data: result });
    });
  }

  function reset() {
    setCode("");
    setError(null);
    setStep({ kind: "form" });
    try {
      window.history.replaceState(null, "", "/canjear");
    } catch {
      // sin historial: no importa
    }
    setTimeout(() => codeRef.current?.focus(), 0);
  }

  function forgetPin() {
    storePin(null);
    setHasStoredPin(false);
    setPin("");
    setTimeout(() => pinRef.current?.focus(), 0);
  }

  if (step.kind === "done") {
    return (
      <div className="redeem-done" role="status" aria-live="polite">
        <div className="redeem-done-icon" aria-hidden="true">
          ✅
        </div>
        <h2>Entregado</h2>
        <p>
          Ya puedes darle el <strong>{step.data.product}</strong> al cliente.
        </p>
        <p className="redeem-fine">
          Código {step.data.code}
          {step.data.deliveredLabel ? ` · ${step.data.deliveredLabel}` : ""}
        </p>
        <button type="button" className="landing-button redeem-big" onClick={reset}>
          Validar otro código
        </button>
      </div>
    );
  }

  if (step.kind === "verified") {
    const data = step.data;
    return (
      <div className="redeem-card">
        {data.photoUrl && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={data.photoUrl} alt="" className="redeem-photo" />
        )}
        <div className="redeem-card-body">
          <span className="redeem-ok-badge">Código válido · {data.code}</span>
          <h2>{data.product}</h2>
          <p className="redeem-merchant">{data.merchant}</p>
          <dl className="redeem-facts">
            <div>
              <dt>Valor</dt>
              <dd>{data.valueLabel}</dd>
            </div>
            <div>
              <dt>Vence el</dt>
              <dd>{data.expiresLabel}</dd>
            </div>
          </dl>
          {error && (
            <p className="landing-error" role="alert">
              {error}
            </p>
          )}
          <button
            type="button"
            className="landing-button redeem-big"
            disabled={isPending}
            onClick={() => run(true)}
          >
            {isPending ? "Confirmando…" : "Confirmar entrega"}
          </button>
          <button
            type="button"
            className="landing-button ghost redeem-big"
            disabled={isPending}
            onClick={() => {
              setError(null);
              setStep({ kind: "form" });
            }}
          >
            Volver
          </button>
          <p className="redeem-fine">Confirma solo cuando le entregues el producto: el código ya no se podrá usar.</p>
        </div>
      </div>
    );
  }

  return (
    <form
      className="redeem-form"
      onSubmit={(event) => {
        event.preventDefault();
        if (canVerify) run(false);
      }}
    >
      <div className="landing-field">
        <label htmlFor="redeem-code">Código del cliente</label>
        <input
          ref={codeRef}
          id="redeem-code"
          name="code"
          className="redeem-code-input"
          type="text"
          value={code}
          onChange={(event) => setCode(normalizeCode(event.target.value))}
          placeholder="ABC123"
          maxLength={12}
          autoComplete="off"
          autoCorrect="off"
          autoCapitalize="characters"
          spellCheck={false}
          enterKeyHint="next"
          required
        />
      </div>

      <div className="landing-field">
        <label htmlFor="redeem-pin">PIN del comercio</label>
        <input
          ref={pinRef}
          id="redeem-pin"
          name="pin"
          className="redeem-pin-input"
          type="password"
          inputMode="numeric"
          pattern="[0-9]*"
          value={pin}
          onChange={(event) => setPin(normalizePin(event.target.value))}
          placeholder="••••••"
          maxLength={6}
          autoComplete="off"
          enterKeyHint="go"
          required
        />
      </div>

      <div className="redeem-remember">
        <label>
          <input type="checkbox" checked={remember} onChange={(event) => setRemember(event.target.checked)} />
          Recordar el PIN en este dispositivo
        </label>
        {hasStoredPin && (
          <button type="button" className="redeem-link" onClick={forgetPin}>
            Olvidar el PIN
          </button>
        )}
      </div>

      {error && (
        <p className="landing-error" role="alert">
          {error}
        </p>
      )}

      <button type="submit" className="landing-button redeem-big" disabled={!canVerify}>
        {isPending ? "Verificando…" : "Verificar"}
      </button>
    </form>
  );
}
