"use client";

import { useEffect, useState } from "react";

type InstallEvent = Event & { prompt: () => Promise<void>; userChoice: Promise<{ outcome: string }> };

const DISMISS_KEY = "monavi-caja-install-dismissed";

/// Registra el service worker y ofrece instalar "MonAvi Caja":
/// - Android/Chrome: boton "Instalar" (evento beforeinstallprompt).
/// - iPhone/iPad (Safari): explica "Compartir → Agregar a inicio".
/// No aparece si ya esta instalada (modo standalone) o si la cerraron.
export default function InstallPrompt() {
  const [installEvent, setInstallEvent] = useState<InstallEvent | null>(null);
  const [showIosHint, setShowIosHint] = useState(false);
  const [hidden, setHidden] = useState(true);

  useEffect(() => {
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/canjear-sw.js", { scope: "/canjear" }).catch(() => {});
    }

    const standalone =
      window.matchMedia("(display-mode: standalone)").matches ||
      (navigator as Navigator & { standalone?: boolean }).standalone === true;
    let dismissed = false;
    try {
      dismissed = localStorage.getItem(DISMISS_KEY) === "1";
    } catch {
      dismissed = false;
    }
    if (standalone || dismissed) return;

    const isIos = /iphone|ipad|ipod/i.test(navigator.userAgent) ||
      (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
    if (isIos) {
      setShowIosHint(true);
      setHidden(false);
    }

    const onPrompt = (event: Event) => {
      event.preventDefault();
      setInstallEvent(event as InstallEvent);
      setHidden(false);
    };
    window.addEventListener("beforeinstallprompt", onPrompt);
    return () => window.removeEventListener("beforeinstallprompt", onPrompt);
  }, []);

  function dismiss() {
    setHidden(true);
    try {
      localStorage.setItem(DISMISS_KEY, "1");
    } catch {
      // sin almacenamiento: solo se oculta por ahora
    }
  }

  async function install() {
    if (!installEvent) return;
    await installEvent.prompt();
    await installEvent.userChoice.catch(() => null);
    setInstallEvent(null);
    setHidden(true);
  }

  if (hidden || (!installEvent && !showIosHint)) return null;

  return (
    <div className="install-banner" role="dialog" aria-label="Instalar MonAvi Caja">
      <img src="/caja/icon-192.png" alt="" width={44} height={44} />
      <div className="install-text">
        <strong>Instala MonAvi Caja</strong>
        {installEvent ? (
          <span>Tenla en tu pantalla de inicio para canjear más rápido.</span>
        ) : (
          <span>
            Toca <b>Compartir</b> <span aria-hidden>⬆︎</span> y luego <b>Agregar a inicio</b>.
          </span>
        )}
      </div>
      {installEvent && (
        <button type="button" className="install-button" onClick={install}>
          Instalar
        </button>
      )}
      <button type="button" className="install-close" onClick={dismiss} aria-label="Cerrar">
        ✕
      </button>
    </div>
  );
}
