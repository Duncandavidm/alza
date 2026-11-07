"use client";

import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import {
  endShift,
  redeemCode,
  searchPending,
  startShift,
  type PendingRedemption,
  type RedeemResult,
} from "./actions";
import Scanner from "./Scanner";

// "MonAvi Caja": app del cajero. Sin turno -> "Iniciar turno" (RUC + PIN).
// Con turno -> Escanear / Buscar cliente / Escribir codigo -> tarjeta de
// confirmacion -> "Entregar". Todas las RPC van por server actions.

const AUTO_RETURN_MS = 2500;
const SEARCH_DEBOUNCE_MS = 300;
const CAMERA_ERROR = "No pudimos acceder a la cámara. Revisa los permisos del navegador.";

type Verified = Extract<RedeemResult, { ok: true }>;
type Origin = "scan" | "search" | "type";

type Screen =
  | { kind: "login" }
  | { kind: "pin" }
  | { kind: "home" }
  | { kind: "scan" }
  | { kind: "search" }
  | { kind: "confirm"; code: string; origin: Origin; customer: string | null };

const normalizeCode = (value: string) =>
  value
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 6);
const normalizePin = (value: string) => value.replace(/\D/g, "").slice(0, 6);

function clearUrlCode() {
  try {
    if (window.location.search) window.history.replaceState(null, "", "/canjear");
  } catch {
    // sin historial: no importa
  }
}

type Props = { initialCode: string; initialMerchant: string | null };

export default function CajaApp({ initialCode, initialMerchant }: Props) {
  const [merchant, setMerchant] = useState<string | null>(initialMerchant);
  const [pendingCode, setPendingCode] = useState(initialMerchant ? "" : initialCode);
  const [screen, setScreen] = useState<Screen>(() =>
    initialMerchant
      ? initialCode.length === 6
        ? { kind: "confirm", code: initialCode, origin: "type", customer: null }
        : { kind: "home" }
      : { kind: "login" }
  );
  const [flash, setFlash] = useState<string | null>(null);

  useEffect(() => {
    if (initialMerchant) clearUrlCode();
  }, [initialMerchant]);

  const goHome = useCallback((message?: string) => {
    setFlash(message ?? null);
    setScreen({ kind: "home" });
  }, []);

  const sessionExpired = useCallback(() => {
    setMerchant(null);
    setFlash("Tu turno terminó. Inicia turno de nuevo.");
    setScreen({ kind: "login" });
  }, []);

  const openConfirm = useCallback((code: string, origin: Origin, customer: string | null = null) => {
    setFlash(null);
    setScreen({ kind: "confirm", code, origin, customer });
  }, []);

  function onLoggedIn(name: string) {
    setMerchant(name);
    setFlash(null);
    const code = pendingCode;
    setPendingCode("");
    clearUrlCode();
    if (code.length === 6) setScreen({ kind: "confirm", code, origin: "type", customer: null });
    else setScreen({ kind: "home" });
  }

  return (
    <div className="caja">
      {merchant && screen.kind !== "login" && screen.kind !== "pin" && (
        <ShiftHeader
          merchant={merchant}
          onClosed={() => {
            setMerchant(null);
            setFlash(null);
            setScreen({ kind: "login" });
          }}
        />
      )}

      <main className="caja-main">
        {screen.kind === "login" && (
          <LoginScreen
            notice={flash}
            pendingCode={pendingCode}
            onLoggedIn={onLoggedIn}
            onUsePin={() => setScreen({ kind: "pin" })}
          />
        )}

        {screen.kind === "pin" && (
          <PinFallback
            initialCode={pendingCode}
            onBack={() => setScreen({ kind: "login" })}
            onDelivered={(name) => {
              // merchant_redeem abre el turno con el primer PIN correcto.
              setPendingCode("");
              clearUrlCode();
              if (name) setMerchant(name);
              setScreen(name ? { kind: "home" } : { kind: "login" });
            }}
          />
        )}

        {screen.kind === "home" && (
          <HomeScreen
            notice={flash}
            onScan={() => {
              setFlash(null);
              setScreen({ kind: "scan" });
            }}
            onSearch={() => {
              setFlash(null);
              setScreen({ kind: "search" });
            }}
            onCode={(code) => openConfirm(code, "type")}
          />
        )}

        {screen.kind === "scan" && (
          <Scanner
            onCode={(code) => openConfirm(code, "scan")}
            onCancel={() => goHome()}
            onCameraError={(message) => goHome(message || CAMERA_ERROR)}
          />
        )}

        {screen.kind === "search" && (
          <SearchScreen
            onBack={() => goHome()}
            onPick={(item) => openConfirm(item.code, "search", item.customer)}
            onExpired={sessionExpired}
          />
        )}

        {screen.kind === "confirm" && (
          <ConfirmScreen
            key={screen.code}
            code={screen.code}
            customer={screen.customer}
            onBack={() => (screen.origin === "search" ? setScreen({ kind: "search" }) : goHome())}
            onDone={() => (screen.origin === "scan" ? setScreen({ kind: "scan" }) : goHome())}
            onExpired={sessionExpired}
          />
        )}
      </main>
    </div>
  );
}

/* ------------------------------------------------------------------ */

function ShiftHeader({ merchant, onClosed }: { merchant: string; onClosed: () => void }) {
  const [isPending, startTransition] = useTransition();
  return (
    <header className="caja-header">
      <div className="caja-header-text">
        <span>Has iniciado sesión como:</span>
        <strong>{merchant}</strong>
      </div>
      <button
        type="button"
        className="caja-link"
        disabled={isPending}
        onClick={() =>
          startTransition(async () => {
            await endShift();
            onClosed();
          })
        }
      >
        {isPending ? "Cerrando…" : "Cerrar turno"}
      </button>
    </header>
  );
}

/* ------------------------------------------------------------------ */

function LoginScreen({
  notice,
  pendingCode,
  onLoggedIn,
  onUsePin,
}: {
  notice: string | null;
  pendingCode: string;
  onLoggedIn: (merchant: string) => void;
  onUsePin: () => void;
}) {
  const [ruc, setRuc] = useState("");
  const [pin, setPin] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const canSubmit = ruc.trim().length >= 3 && pin.length === 6 && !isPending;

  return (
    <section className="caja-login">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img className="caja-logo" src="/caja/icon-192.png" alt="" width={88} height={88} />
      <h1 className="caja-title">MonAvi Caja</h1>
      <p className="caja-dim">Inicia el turno con el RUC y el PIN de tu comercio.</p>

      {pendingCode.length === 6 && (
        <p className="caja-info" role="status">
          Después de entrar validaremos el código <strong>{pendingCode}</strong>.
        </p>
      )}
      {notice && !error && (
        <p className="caja-info" role="status">
          {notice}
        </p>
      )}

      <form
        className="caja-form"
        onSubmit={(event) => {
          event.preventDefault();
          if (!canSubmit) return;
          setError(null);
          startTransition(async () => {
            const result = await startShift({ ruc, pin });
            if (!result.ok) {
              setError(result.error);
              setPin("");
              return;
            }
            onLoggedIn(result.merchant);
          });
        }}
      >
        <label className="caja-field">
          <span>RUC</span>
          <input
            type="text"
            value={ruc}
            onChange={(event) => setRuc(event.target.value)}
            autoComplete="username"
            autoCapitalize="characters"
            spellCheck={false}
            enterKeyHint="next"
            placeholder="Ej. 155555555-2-2020"
            required
          />
        </label>
        <label className="caja-field">
          <span>PIN</span>
          <input
            type="password"
            inputMode="numeric"
            pattern="[0-9]*"
            value={pin}
            onChange={(event) => setPin(normalizePin(event.target.value))}
            autoComplete="current-password"
            maxLength={6}
            enterKeyHint="go"
            placeholder="••••••"
            className="caja-pin"
            required
          />
        </label>
        {error && (
          <p className="caja-error" role="alert">
            {error}
          </p>
        )}
        <button type="submit" className="caja-btn caja-btn-primary" disabled={!canSubmit}>
          {isPending ? "Entrando…" : "Entrar"}
        </button>
      </form>

      {pendingCode.length === 6 && (
        <button type="button" className="caja-link" onClick={onUsePin}>
          Validar solo este código con el PIN
        </button>
      )}

      <p className="caja-fine">
        ¿No tienes PIN? Pídelo a MonAvi: <a href="mailto:hola@maday.app">hola@maday.app</a>
      </p>
    </section>
  );
}

/* ------------------------------------------------------------------ */

function HomeScreen({
  notice,
  onScan,
  onSearch,
  onCode,
}: {
  notice: string | null;
  onScan: () => void;
  onSearch: () => void;
  onCode: (code: string) => void;
}) {
  const [typing, setTyping] = useState(false);
  const [code, setCode] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (typing) inputRef.current?.focus();
  }, [typing]);

  return (
    <section className="caja-home">
      {notice && (
        <p className="caja-error" role="alert">
          {notice}
        </p>
      )}
      <button type="button" className="caja-btn caja-btn-primary caja-btn-xl" onClick={onScan}>
        ESCANEAR
      </button>
      <button type="button" className="caja-btn caja-btn-secondary caja-btn-lg" onClick={onSearch}>
        BUSCAR CLIENTE
      </button>

      {typing ? (
        <form
          className="caja-type"
          onSubmit={(event) => {
            event.preventDefault();
            if (code.length === 6) onCode(code);
          }}
        >
          <label className="caja-field">
            <span>Código del cliente</span>
            <input
              ref={inputRef}
              type="text"
              className="caja-code"
              value={code}
              onChange={(event) => {
                const next = normalizeCode(event.target.value);
                setCode(next);
                if (next.length === 6) onCode(next);
              }}
              placeholder="ABC123"
              maxLength={12}
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="characters"
              spellCheck={false}
              enterKeyHint="go"
            />
          </label>
          <button
            type="button"
            className="caja-link"
            onClick={() => {
              setTyping(false);
              setCode("");
            }}
          >
            Cancelar
          </button>
        </form>
      ) : (
        <button type="button" className="caja-link caja-type-link" onClick={() => setTyping(true)}>
          Escribir código
        </button>
      )}
    </section>
  );
}

/* ------------------------------------------------------------------ */

function SearchScreen({
  onBack,
  onPick,
  onExpired,
}: {
  onBack: () => void;
  onPick: (item: PendingRedemption) => void;
  onExpired: () => void;
}) {
  const [query, setQuery] = useState("");
  const [items, setItems] = useState<PendingRedemption[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const requestId = useRef(0);
  const onExpiredRef = useRef(onExpired);
  useEffect(() => {
    onExpiredRef.current = onExpired;
  });

  const trimmed = query.trim();
  // Con 1 caracter no se busca: se mantiene la lista anterior.
  const effective = trimmed.length >= 2 ? trimmed : trimmed.length === 0 ? "" : null;

  useEffect(() => {
    if (effective === null) return;
    const id = ++requestId.current;
    const timer = setTimeout(
      async () => {
        setLoading(true);
        const result = await searchPending({ query: effective });
        if (id !== requestId.current) return;
        setLoading(false);
        if (!result.ok) {
          if (result.sessionExpired) onExpiredRef.current();
          else setError(result.error);
          return;
        }
        setError(null);
        setItems(result.items);
      },
      effective === "" && items === null ? 0 : SEARCH_DEBOUNCE_MS
    );
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [effective]);

  return (
    <section className="caja-search">
      <div className="caja-search-bar">
        <button type="button" className="caja-back" onClick={onBack} aria-label="Volver">
          ←
        </button>
        <input
          type="search"
          autoFocus
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Nombre, teléfono o código"
          aria-label="Nombre, teléfono o código"
          autoComplete="off"
          autoCorrect="off"
          spellCheck={false}
          enterKeyHint="search"
        />
      </div>

      {error && (
        <p className="caja-error" role="alert">
          {error}
        </p>
      )}

      <p className="caja-dim caja-search-status" role="status" aria-live="polite">
        {loading
          ? "Buscando…"
          : items && items.length > 0
            ? trimmed
              ? `${items.length} ${items.length === 1 ? "resultado" : "resultados"}`
              : `${items.length} ${items.length === 1 ? "canje pendiente" : "canjes pendientes"}`
            : items
              ? trimmed
                ? "No encontramos canjes pendientes con esa búsqueda."
                : "No hay canjes pendientes en tu comercio."
              : ""}
      </p>

      {items && items.length > 0 && (
        <ul className="caja-results">
          {items.map((item) => (
            <li key={item.code}>
              <button type="button" className="caja-result" onClick={() => onPick(item)}>
                {item.photoUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={item.photoUrl} alt="" className="caja-thumb" loading="lazy" />
                ) : (
                  <span className="caja-thumb caja-thumb-empty" aria-hidden="true">
                    🎟️
                  </span>
                )}
                <span className="caja-result-body">
                  <strong>{item.customer}</strong>
                  <span>{item.product}</span>
                  <span className="caja-result-meta">
                    {item.isGift && <span className="caja-gift">🎁 Regalo</span>}
                    {item.phoneHint && <span>{item.phoneHint}</span>}
                    <span>Vence el {item.expiresLabel}</span>
                  </span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/* ------------------------------------------------------------------ */

type ConfirmState =
  | { kind: "loading" }
  | { kind: "preview"; data: Verified }
  | { kind: "delivering"; data: Verified }
  | { kind: "done"; data: Verified }
  | { kind: "error"; message: string };

function ConfirmScreen({
  code,
  customer,
  onBack,
  onDone,
  onExpired,
}: {
  code: string;
  customer: string | null;
  onBack: () => void;
  onDone: () => void;
  onExpired: () => void;
}) {
  const [state, setState] = useState<ConfirmState>({ kind: "loading" });
  const onExpiredRef = useRef(onExpired);
  const onDoneRef = useRef(onDone);
  useEffect(() => {
    onExpiredRef.current = onExpired;
    onDoneRef.current = onDone;
  });

  useEffect(() => {
    let active = true;
    redeemCode({ code, confirm: false, requireSession: true }).then((result) => {
      if (!active) return;
      if (!result.ok) {
        if (result.sessionExpired) return onExpiredRef.current();
        setState({ kind: "error", message: result.product ? `${result.error} (${result.product})` : result.error });
        return;
      }
      setState({ kind: "preview", data: result });
    });
    return () => {
      active = false;
    };
  }, [code]);

  useEffect(() => {
    if (state.kind !== "done") return;
    const timer = setTimeout(() => onDoneRef.current(), AUTO_RETURN_MS);
    return () => clearTimeout(timer);
  }, [state.kind]);

  async function deliver(data: Verified) {
    setState({ kind: "delivering", data });
    const result = await redeemCode({ code: data.code, confirm: true, requireSession: true });
    if (!result.ok) {
      if (result.sessionExpired) return onExpiredRef.current();
      setState({ kind: "error", message: result.product ? `${result.error} (${result.product})` : result.error });
      return;
    }
    try {
      navigator.vibrate?.(60);
    } catch {
      // sin vibracion
    }
    setState({ kind: "done", data: result });
  }

  if (state.kind === "loading") {
    return (
      <section className="caja-card caja-center" role="status" aria-live="polite">
        <div className="caja-spinner" aria-hidden="true" />
        <p className="caja-dim">Verificando el código {code}…</p>
      </section>
    );
  }

  if (state.kind === "error") {
    return (
      <section className="caja-card caja-center">
        <div className="caja-x" aria-hidden="true">
          ✕
        </div>
        <p className="caja-error caja-error-big" role="alert">
          {state.message}
        </p>
        <p className="caja-dim">Código {code}</p>
        <button type="button" className="caja-btn caja-btn-secondary" onClick={onBack}>
          Volver
        </button>
      </section>
    );
  }

  if (state.kind === "done") {
    return (
      <section className="caja-card caja-center caja-done" role="status" aria-live="polite">
        <div className="caja-check" aria-hidden="true">
          ✓
        </div>
        <h2>¡Entregado!</h2>
        <p>
          Ya puedes darle <strong>{state.data.product}</strong> al cliente.
        </p>
        <p className="caja-fine">Código {state.data.code}</p>
      </section>
    );
  }

  const data = state.data;
  const delivering = state.kind === "delivering";
  return (
    <section className="caja-card caja-confirm">
      {data.photoUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={data.photoUrl} alt="" className="caja-photo" />
      ) : (
        <div className="caja-photo caja-photo-empty" aria-hidden="true">
          🎟️
        </div>
      )}
      <div className="caja-confirm-body">
        {data.isGift && <span className="caja-gift caja-gift-big">🎁 Regalo de MonAvi</span>}
        <h2 className="caja-product">{data.product}</h2>
        {customer && <p className="caja-customer">{customer}</p>}
        <dl className="caja-facts">
          <div>
            <dt>Valor</dt>
            <dd>{data.isGift ? `Gratis (${data.valueLabel})` : data.valueLabel}</dd>
          </div>
          <div>
            <dt>Vence el</dt>
            <dd>{data.expiresLabel}</dd>
          </div>
          <div>
            <dt>Código</dt>
            <dd className="caja-mono">{data.code}</dd>
          </div>
        </dl>
        <button
          type="button"
          className="caja-btn caja-btn-deliver"
          disabled={delivering}
          onClick={() => deliver(data)}
        >
          {delivering ? "Entregando…" : `Entregar ${data.product}`}
        </button>
        <button type="button" className="caja-btn caja-btn-secondary" disabled={delivering} onClick={onBack}>
          Volver
        </button>
        <p className="caja-fine">Toca “Entregar” solo cuando le des el producto: el código ya no se podrá usar.</p>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */

function PinFallback({
  initialCode,
  onBack,
  onDelivered,
}: {
  initialCode: string;
  onBack: () => void;
  onDelivered: (merchant: string | null) => void;
}) {
  const [code, setCode] = useState(initialCode);
  const [pin, setPin] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [verified, setVerified] = useState<Verified | null>(null);
  const [done, setDone] = useState<Verified | null>(null);
  const [isPending, startTransition] = useTransition();
  const onDeliveredRef = useRef(onDelivered);
  useEffect(() => {
    onDeliveredRef.current = onDelivered;
  });

  useEffect(() => {
    if (!done) return;
    const timer = setTimeout(() => onDeliveredRef.current(done.session?.merchant || null), AUTO_RETURN_MS);
    return () => clearTimeout(timer);
  }, [done]);

  function run(confirm: boolean) {
    setError(null);
    startTransition(async () => {
      const result = await redeemCode({ code, pin, confirm });
      if (!result.ok) {
        setError(result.product ? `${result.error} (${result.product})` : result.error);
        setVerified(null);
        return;
      }
      if (result.delivered) setDone(result);
      else setVerified(result);
    });
  }

  if (done) {
    return (
      <section className="caja-card caja-center caja-done" role="status" aria-live="polite">
        <div className="caja-check" aria-hidden="true">
          ✓
        </div>
        <h2>¡Entregado!</h2>
        <p>
          Ya puedes darle <strong>{done.product}</strong> al cliente.
        </p>
      </section>
    );
  }

  if (verified) {
    return (
      <section className="caja-card caja-confirm">
        {verified.photoUrl && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={verified.photoUrl} alt="" className="caja-photo" />
        )}
        <div className="caja-confirm-body">
          {verified.isGift && <span className="caja-gift caja-gift-big">🎁 Regalo de MonAvi</span>}
          <h2 className="caja-product">{verified.product}</h2>
          <dl className="caja-facts">
            <div>
              <dt>Valor</dt>
              <dd>{verified.isGift ? `Gratis (${verified.valueLabel})` : verified.valueLabel}</dd>
            </div>
            <div>
              <dt>Vence el</dt>
              <dd>{verified.expiresLabel}</dd>
            </div>
          </dl>
          {error && (
            <p className="caja-error" role="alert">
              {error}
            </p>
          )}
          <button type="button" className="caja-btn caja-btn-deliver" disabled={isPending} onClick={() => run(true)}>
            {isPending ? "Entregando…" : `Entregar ${verified.product}`}
          </button>
          <button
            type="button"
            className="caja-btn caja-btn-secondary"
            disabled={isPending}
            onClick={() => setVerified(null)}
          >
            Volver
          </button>
        </div>
      </section>
    );
  }

  return (
    <section className="caja-login">
      <h1 className="caja-title">Validar con PIN</h1>
      <p className="caja-dim">Escribe el código del cliente y el PIN de 6 dígitos de tu comercio.</p>
      <form
        className="caja-form"
        onSubmit={(event) => {
          event.preventDefault();
          if (code.length === 6 && pin.length === 6 && !isPending) run(false);
        }}
      >
        <label className="caja-field">
          <span>Código del cliente</span>
          <input
            type="text"
            className="caja-code"
            value={code}
            onChange={(event) => setCode(normalizeCode(event.target.value))}
            placeholder="ABC123"
            maxLength={12}
            autoComplete="off"
            autoCapitalize="characters"
            spellCheck={false}
          />
        </label>
        <label className="caja-field">
          <span>PIN del comercio</span>
          <input
            type="password"
            inputMode="numeric"
            pattern="[0-9]*"
            className="caja-pin"
            value={pin}
            onChange={(event) => setPin(normalizePin(event.target.value))}
            placeholder="••••••"
            maxLength={6}
            autoComplete="off"
            autoFocus
          />
        </label>
        {error && (
          <p className="caja-error" role="alert">
            {error}
          </p>
        )}
        <button
          type="submit"
          className="caja-btn caja-btn-primary"
          disabled={code.length !== 6 || pin.length !== 6 || isPending}
        >
          {isPending ? "Verificando…" : "Verificar código"}
        </button>
      </form>
      <button type="button" className="caja-link" onClick={onBack}>
        Volver a iniciar turno
      </button>
    </section>
  );
}
