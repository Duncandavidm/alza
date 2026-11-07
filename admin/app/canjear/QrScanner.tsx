"use client";

import { useEffect, useRef, useState } from "react";

// Escaner de QR con la camara trasera. Usa la API nativa BarcodeDetector
// cuando existe (Chrome/Android, Safari reciente) y si no, la libreria
// qr-scanner (decodifica en un web worker; se carga solo si hace falta).
// Escanea sin parar hasta el primer codigo valido, vibra y se detiene.

type DetectedBarcode = { rawValue: string };
type NativeDetector = { detect: (source: HTMLVideoElement) => Promise<DetectedBarcode[]> };
type NativeDetectorClass = {
  new (options: { formats: string[] }): NativeDetector;
  getSupportedFormats?: () => Promise<string[]>;
};

/// "https://monavi.maday.app/canjear?code=ABC123" o "ABC123" -> "ABC123".
export function extractRedeemCode(text: string): string | null {
  const raw = text.trim();
  let candidate = raw;
  try {
    const url = new URL(raw);
    candidate = url.searchParams.get("code") ?? "";
  } catch {
    // no es una URL: se usa el texto tal cual
  }
  const code = candidate.toUpperCase().replace(/[^A-Z0-9]/g, "");
  return code.length === 6 ? code : null;
}

async function nativeDetector(): Promise<NativeDetector | null> {
  const Detector = (window as unknown as { BarcodeDetector?: NativeDetectorClass }).BarcodeDetector;
  if (!Detector) return null;
  try {
    const formats = (await Detector.getSupportedFormats?.()) ?? ["qr_code"];
    if (!formats.includes("qr_code")) return null;
    return new Detector({ formats: ["qr_code"] });
  } catch {
    return null;
  }
}

function cameraErrorMessage(error: unknown): string {
  const name = (error as { name?: string })?.name ?? "";
  if (name === "NotAllowedError" || name === "SecurityError") {
    return "No hay permiso para usar la cámara. Actívalo en el navegador (ícono junto a la dirección) o escribe el código.";
  }
  if (name === "NotFoundError" || name === "OverconstrainedError" || /camera not found/i.test(String(error))) {
    return "Este dispositivo no tiene cámara disponible. Escribe el código.";
  }
  if (name === "NotReadableError") return "La cámara está en uso por otra app. Ciérrala e intenta de nuevo.";
  return "No se pudo abrir la cámara. Escribe el código.";
}

export default function QrScanner({ onCode, onClose }: { onCode: (code: string) => void; onClose: () => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const onCodeRef = useRef(onCode);
  onCodeRef.current = onCode;
  const [error, setError] = useState<string | null>(null);
  const [starting, setStarting] = useState(true);

  useEffect(() => {
    let cancelled = false;
    let stream: MediaStream | null = null;
    let timer: ReturnType<typeof setTimeout> | null = null;
    let library: { stop: () => void; destroy: () => void } | null = null;
    let found = false;

    const finish = (code: string) => {
      if (found || cancelled) return;
      found = true;
      try {
        navigator.vibrate?.(120);
      } catch {
        // sin vibracion
      }
      stopAll();
      onCodeRef.current(code);
    };

    const stopAll = () => {
      if (timer) clearTimeout(timer);
      timer = null;
      stream?.getTracks().forEach((track) => track.stop());
      stream = null;
      if (library) {
        library.stop();
        library.destroy();
        library = null;
      }
    };

    async function start() {
      const video = videoRef.current;
      if (!video) return;
      if (!navigator.mediaDevices?.getUserMedia) {
        setError("Este navegador no permite usar la cámara (se necesita https). Escribe el código.");
        setStarting(false);
        return;
      }

      const detector = await nativeDetector();
      if (cancelled) return;

      if (detector) {
        try {
          stream = await navigator.mediaDevices.getUserMedia({
            video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 }, height: { ideal: 720 } },
            audio: false,
          });
          if (cancelled) return stopAll();
          video.srcObject = stream;
          await video.play();
          setStarting(false);
          const tick = async () => {
            if (cancelled || found) return;
            try {
              if (video.readyState >= 2) {
                const codes = await detector.detect(video);
                for (const barcode of codes) {
                  const code = extractRedeemCode(barcode.rawValue ?? "");
                  if (code) return finish(code);
                }
              }
            } catch {
              // cuadro ilegible: se sigue intentando
            }
            timer = setTimeout(tick, 120);
          };
          void tick();
        } catch (err) {
          if (!cancelled) {
            setError(cameraErrorMessage(err));
            setStarting(false);
          }
        }
        return;
      }

      // Respaldo: qr-scanner (web worker). Maneja su propia camara.
      try {
        const { default: QrScannerLib } = await import("qr-scanner");
        if (cancelled) return;
        const scanner = new QrScannerLib(
          video,
          (result) => {
            const code = extractRedeemCode(result.data ?? "");
            if (code) finish(code);
          },
          { preferredCamera: "environment", maxScansPerSecond: 15, returnDetailedScanResult: true }
        );
        library = scanner;
        await scanner.start();
        if (cancelled) return stopAll();
        setStarting(false);
      } catch (err) {
        if (!cancelled) {
          setError(cameraErrorMessage(err));
          setStarting(false);
        }
      }
    }

    void start();
    return () => {
      cancelled = true;
      stopAll();
    };
  }, []);

  return (
    <div className="qr-scanner">
      <div className="qr-viewport">
        <video ref={videoRef} className="qr-video" muted playsInline autoPlay />
        {!error && <div className="qr-frame" aria-hidden="true" />}
        {starting && !error && <div className="qr-status">Abriendo la cámara…</div>}
      </div>
      {error ? (
        <p className="landing-error" role="alert">
          {error}
        </p>
      ) : (
        <p className="redeem-fine">Apunta al QR del cliente. Se lee solo.</p>
      )}
      <button type="button" className="landing-button ghost redeem-big" onClick={onClose}>
        Escribir el código
      </button>
    </div>
  );
}
