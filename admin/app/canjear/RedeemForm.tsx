"use client";

import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { endShift, redeemCode, type RedeemResult } from "./actions";
import QrScanner from "./QrScanner";

// El PIN se recuerda SOLO en este navegador (localStorage), para que el
// cajero no lo escriba con cada cliente. Con el turno abierto (cookie
// firmada de 12 horas, ver lib/redeem-session.ts) ni siquiera se pide.
const PIN_STORAGE_KEY = "monavi_redeem_pin";
const AUTO_RETURN_MS = 3000;

type Verified = Extract<RedeemResult, { ok: true }>;
type Step =
  | { kind: "form" }
  | { kind: "scan" }
  | { kind: "verified"; data: Verified }
  | { kind: "done"; data: Verified };

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

type Props = { initialCode: string; initialSession: { merchant: string } | null };

export default function RedeemForm({ initialCode, initialSession }: Props) {
  const [code, setCode] = useState(initialCode);
  const [pin, setPin] = useState("");
  const [remember, setRemember] = useState(true);
  const [hasStoredPin, setHasStoredPin] = useState(false);
  const [session, setSession] = useState(initialSession);
  const [step, setStep] = useState<Step>({ kind: "form" });
  const [error, setError] = useState<string | null>(null);
  const [usedScanner, setUsedScanner] = useState(false);
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
    else if (!stored && !initialSession) pinRef.current?.focus();
  }, [initialCode, initialSession]);

  const needsPin = !session;
  const canVerify = code.length === 6 && (!needsPin || pin.length === 6) && !isPending;

  const run = useCallback(
    (codeToCheck: string, confirm: boolean) => {
      setError(null);
      startTransition(async () => {
        const result = await redeemCode({ code: codeToCheck, pin: needsPin ? pin : undefined, confirm });
        if (!result.ok) {
          setError(result.product ? `${result.error} (${result.product})` : result.error);
          // La sesion pudo vencer: vuelve a pedir el PIN.
          if (result.needsPin && session) setSession(null);
          setStep({ kind: "form" });
          return;
        }
        if (needsPin) {
          // PIN correcto: se recuerda (o se olvida) segun la casilla.
          storePin(remember ? pin : null);
          setHasStoredPin(remember);
        }
        if (result.session) setSession(result.session);
        setStep(result.delivered ? { kind: "done", data: result } : { kind: "verified", data: result });
      });
    },
    [needsPin, pin, remember, session]
  );

  const reset = useCallback(
    (openScanner: boolean) => {
      setCode("");
      setError(null);
      setStep(openScanner ? { kind: "scan" } : { kind: "form" });
      try {
        window.history.replaceState(null, "", "/canjear");
      } catch {
        // sin historial: no importa
      }
      if (!openScanner) setTimeout(() => codeRef.current?.focus(), 0);
    },
    []
  );

  // Despues de entregar: vuelve solo al escaner (o al formulario) para el
  // siguiente cliente.
  useEffect(() => {
    if (step.kind !== "done") return;
    const timer = setTimeout(() => reset(usedScanner && Boolean(session)), AUTO_RETURN_MS);
    return () => clearTimeout(timer);
  }, [step, usedScanner, session, reset]);

  function onScanned(scanned: string) {
    setUsedScanner(true);
    setCode(scanned);
    if (!needsPin || pin.length === 6) {
      setStep({ kind: "form" });
      run(scanned, false);
    } else {
      setStep({ kind: "form" });
      setTimeout(() => pinRef.current?.focus(), 0);
    }
  }

  function closeShift() {
    startTransition(async () => {
      await endShift();
      setSession(null);
      setStep({ kind: "form" });
      setTimeout(() => pinRef.current?.focus(), 0);
    });
  }

  function forgetPin() {
    storePin(null);
    setHasStoredPin(false);
    setPin("");
    setTimeout(() => pinRef.current?.focus(), 0);
  }

  const sessionBar = session ? (
    <div className="redeem-session" role="status">
      <span>
        <strong>Caja de {session.merchant || "tu comercio"}</strong> · sesión activa
      </span>
      <button type="button" className="redeem-link" onClick={closeShift} disabled={isPending}>
        Cerrar turno
      </button>
    </div>
  ) : null;

  if (step.kind === "done") {
    return (
      <>
        {sessionBar}
        <div className="redeem-done" role="status" aria-live="polite">
          <div className="redeem-check" aria-hidden="true">
            ✓
          </div>
          <h2>Entregado</h2>
          <p>
            Ya puedes darle <strong>{step.data.product}</strong> al cliente.
          </p>
          <p className="redeem-fine">
            Código {step.data.code}
            {step.data.deliveredLabel ? ` · ${step.data.deliveredLabel}` : ""}
          </p>
          <button
            type="button"
            className="landing-button redeem-big"
            onClick={() => reset(usedScanner && Boolean(session))}
          >
            Siguiente cliente
          </button>
          <p className="redeem-fine">Volviendo solo en unos segundos…</p>
        </div>
      </>
    );
  }

  if (step.kind === "verified") {
    const data = step.data;
    return (
      <>
        {sessionBar}
        <div className="redeem-card">
          {data.photoUrl && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={data.photoUrl} alt="" className="redeem-photo" />
          )}
          <div className="redeem-card-body">
            <span className="redeem-ok-badge">Código válido · {data.code}</span>
            {data.isGift && <span className="redeem-gift">🎁 Regalo de MonAvi</span>}
            <h2 className="redeem-product">{data.product}</h2>
            <p className="redeem-merchant">{data.merchant}</p>
            <dl className="redeem-facts">
              <div>
                <dt>Valor</dt>
                <dd>{data.isGift ? `Gratis (${data.valueLabel})` : data.valueLabel}</dd>
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
              className="landing-button redeem-big redeem-deliver"
              disabled={isPending}
              onClick={() => run(data.code, true)}
            >
              {isPending ? "Confirmando…" : "Entregar"}
            </button>
            <button
              type="button"
              className="landing-button ghost redeem-big"
              disabled={isPending}
              onClick={() => reset(false)}
            >
              Cancelar
            </button>
            <p className="redeem-fine">Toca “Entregar” solo cuando le des el producto: el código ya no se podrá usar.</p>
          </div>
        </div>
      </>
    );
  }

  if (step.kind === "scan") {
    return (
      <>
        {sessionBar}
        {needsPin && pin.length !== 6 && (
          <p className="redeem-fine" style={{ marginBottom: 12 }}>
            Después de escanear te pediremos el PIN del comercio una sola vez por turno.
          </p>
        )}
        <QrScanner onCode={onScanned} onClose={() => setStep({ kind: "form" })} />
      </>
    );
  }

  return (
    <>
      {sessionBar}
      <form
        className="redeem-form"
        onSubmit={(event) => {
          event.preventDefault();
          if (canVerify) run(code, false);
        }}
      >
        <button
          type="button"
          className="landing-button redeem-big redeem-scan"
          onClick={() => {
            setError(null);
            setStep({ kind: "scan" });
          }}
          disabled={isPending}
        >
          📷 Escanear QR
        </button>

        <div className="landing-field">
          <label htmlFor="redeem-code">o escribe el código del cliente</label>
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
            enterKeyHint={needsPin ? "next" : "go"}
          />
        </div>

        {needsPin && (
          <>
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
              />
              <small className="redeem-fine" style={{ display: "block", marginTop: 6, textAlign: "left" }}>
                Se pide una vez por turno: después solo escaneas durante 12 horas.
              </small>
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
          </>
        )}

        {error && (
          <p className="landing-error" role="alert">
            {error}
          </p>
        )}

        <button type="submit" className="landing-button ghost redeem-big" disabled={!canVerify}>
          {isPending ? "Verificando…" : "Verificar código"}
        </button>
      </form>
    </>
  );
}
