"use client";

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";

// Celebracion al entregar un canje: lluvia de emojis (CSS) y un sonido
// "cha-ching" + destellos generado con Web Audio (sin archivos). El
// AudioContext se prepara en el toque de "Entregar" (gesto del usuario),
// porque iOS/Chrome no dejan sonar audio sin un toque previo.

const SOUND_KEY = "monavi-caja-sound";
const COUNT_KEY = "monavi-caja-count";
const EMOJIS = ["🎉", "✨", "💚", "🥳", "🎁", "⭐", "💸", "🙌", "🎊", "💰"];

let audioCtx: AudioContext | null = null;

export function soundEnabled(): boolean {
  try {
    return window.localStorage.getItem(SOUND_KEY) !== "off";
  } catch {
    return true;
  }
}

export function setSoundEnabled(on: boolean) {
  try {
    window.localStorage.setItem(SOUND_KEY, on ? "on" : "off");
  } catch {
    // sin almacenamiento: solo dura esta visita
  }
}

/// Llamar dentro del toque (antes de cualquier await).
export function primeAudio() {
  try {
    if (!audioCtx) {
      const Ctx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      if (!Ctx) return;
      audioCtx = new Ctx();
    }
    if (audioCtx.state === "suspended") void audioCtx.resume();
  } catch {
    audioCtx = null;
  }
}

function tone(ctx: AudioContext, freq: number, start: number, length: number, type: OscillatorType, volume: number) {
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(freq, start);
  gain.gain.setValueAtTime(0.0001, start);
  gain.gain.exponentialRampToValueAtTime(volume, start + 0.015);
  gain.gain.exponentialRampToValueAtTime(0.0001, start + length);
  osc.connect(gain).connect(ctx.destination);
  osc.start(start);
  osc.stop(start + length + 0.05);
}

export function playCelebration() {
  if (!soundEnabled()) return;
  primeAudio();
  const ctx = audioCtx;
  if (!ctx) return;
  try {
    const t = ctx.currentTime + 0.02;
    // "cha-ching" de caja registradora
    tone(ctx, 1318.5, t, 0.12, "square", 0.08);
    tone(ctx, 1975.5, t + 0.09, 0.45, "square", 0.07);
    // destellos (Do-Mi-Sol-Do)
    [1046.5, 1318.5, 1568, 2093].forEach((f, i) => tone(ctx, f, t + 0.32 + i * 0.08, 0.35, "triangle", 0.12));
  } catch {
    // sin audio: la celebracion visual basta
  }
}

/// Canjes entregados hoy desde este dispositivo.
export function todayCount(): number {
  try {
    const raw = JSON.parse(window.localStorage.getItem(COUNT_KEY) ?? "null");
    return raw && raw.day === new Date().toDateString() ? Number(raw.n) || 0 : 0;
  } catch {
    return 0;
  }
}

export function bumpTodayCount(): number {
  const n = todayCount() + 1;
  try {
    window.localStorage.setItem(COUNT_KEY, JSON.stringify({ day: new Date().toDateString(), n }));
  } catch {
    // sin almacenamiento
  }
  return n;
}

export function EmojiBurst({ count = 42 }: { count?: number }) {
  type Piece = { emoji: string; x: number; rise: number; rotate: number; delay: number; duration: number; size: number };
  const [pieces, setPieces] = useState<Piece[]>([]);
  // Se arma en el cliente (valores aleatorios): evita diferencias con el HTML del servidor.
  useEffect(() => {
    setPieces(
      Array.from({ length: count }, (_, i) => ({
        emoji: EMOJIS[i % EMOJIS.length],
        x: Math.round((Math.random() * 2 - 1) * 46),
        rise: 30 + Math.round(Math.random() * 40),
        rotate: Math.round((Math.random() * 2 - 1) * 540),
        delay: Math.round(Math.random() * 350),
        duration: 1600 + Math.round(Math.random() * 1100),
        size: 22 + Math.round(Math.random() * 22),
      }))
    );
  }, [count]);
  if (pieces.length === 0) return null;
  // Portal al <body>: asi la tarjeta (animada con transform) no recorta la lluvia.
  return createPortal(
    <div className="caja-burst" aria-hidden="true">
      {pieces.map((p, i) => (
        <span
          key={i}
          style={
            {
              "--x": `${p.x}vw`,
              "--rise": `${p.rise}vh`,
              "--rot": `${p.rotate}deg`,
              animationDelay: `${p.delay}ms`,
              animationDuration: `${p.duration}ms`,
              fontSize: `${p.size}px`,
            } as React.CSSProperties
          }
        >
          {p.emoji}
        </span>
      ))}
    </div>,
    document.body
  );
}

/// "Bip" corto al leer un QR (antes de verificarlo).
export function playScanBeep() {
  if (!soundEnabled()) return;
  primeAudio();
  const ctx = audioCtx;
  if (!ctx) return;
  try {
    const t = ctx.currentTime + 0.01;
    tone(ctx, 1760, t, 0.09, "sine", 0.18);
  } catch {
    // sin audio
  }
}

/// Dos tonos graves cuando el codigo no sirve (vencido, usado, de otro comercio).
export function playErrorSound() {
  if (!soundEnabled()) return;
  primeAudio();
  const ctx = audioCtx;
  if (!ctx) return;
  try {
    const t = ctx.currentTime + 0.01;
    tone(ctx, 330, t, 0.16, "square", 0.07);
    tone(ctx, 247, t + 0.18, 0.28, "square", 0.07);
  } catch {
    // sin audio
  }
}

/// Vibracion. Android usa navigator.vibrate; en iPhone (iOS 18+), que no
/// tiene esa funcion, se usa el toque de un interruptor nativo oculto, que
/// produce la vibracion del sistema. Si nada funciona, no pasa nada.
export function haptic(kind: "light" | "success" | "error" = "light") {
  try {
    if (typeof navigator !== "undefined" && typeof navigator.vibrate === "function") {
      const pattern = kind === "success" ? [60, 40, 120] : kind === "error" ? [120, 60, 120] : 30;
      if (navigator.vibrate(pattern)) return;
    }
  } catch {
    // sigue con el plan B
  }
  iosHapticTick();
  if (kind !== "light") setTimeout(iosHapticTick, 140);
}

function iosHapticTick() {
  try {
    const label = document.createElement("label");
    label.setAttribute("aria-hidden", "true");
    label.style.cssText = "position:fixed;left:-100px;top:0;opacity:0;pointer-events:none;";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.setAttribute("switch", "");
    label.appendChild(input);
    document.body.appendChild(label);
    label.click();
    label.remove();
  } catch {
    // sin vibracion
  }
}

/// Mantiene la pantalla encendida mientras la caja esta abierta (Screen
/// Wake Lock). El sistema lo suelta al pasar a segundo plano; se vuelve a
/// pedir al regresar. Devuelve la funcion para soltarlo.
export function keepScreenAwake(): () => void {
  type Sentinel = { release: () => Promise<void> };
  type WakeLockApi = { request: (type: "screen") => Promise<Sentinel> };
  const api = (navigator as Navigator & { wakeLock?: WakeLockApi }).wakeLock;
  if (!api) return () => {};
  let sentinel: Sentinel | null = null;
  let active = true;
  const request = async () => {
    if (!active || document.visibilityState !== "visible") return;
    try {
      sentinel = await api.request("screen");
    } catch {
      sentinel = null;
    }
  };
  const onVisible = () => {
    if (document.visibilityState === "visible") void request();
  };
  void request();
  document.addEventListener("visibilitychange", onVisible);
  return () => {
    active = false;
    document.removeEventListener("visibilitychange", onVisible);
    void sentinel?.release().catch(() => {});
  };
}

/// La caja corre como app instalada (pantalla de inicio).
export function isInstalledApp(): boolean {
  try {
    return (
      window.matchMedia("(display-mode: standalone)").matches ||
      (navigator as Navigator & { standalone?: boolean }).standalone === true
    );
  } catch {
    return false;
  }
}
