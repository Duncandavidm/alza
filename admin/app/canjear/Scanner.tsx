"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { IScannerControls } from "@zxing/browser";
import type { DecodeHintType as HintType } from "@zxing/library";

// Escaner de QR de "MonAvi Caja" con la camara trasera (@zxing/browser).
// La camara se abre solo cuando el <video> ya esta montado (callback ref +
// efecto) y se apaga (controles + todas las pistas) al cancelar, al
// desmontar o al leer un codigo valido. No se piden restricciones de
// enfoque (focusMode): rompen la camara en algunos Android.

const CODE_RE = /^[A-Z0-9]{6}$/;
const DETECTED_DELAY_MS = 450;

/// "https://monavi.maday.app/canjear?code=ABC123" o "ABC123" -> "ABC123".
export function extractRedeemCode(text: string): string | null {
  const raw = (text ?? "").trim();
  if (!raw) return null;
  let candidate = raw;
  if (/^https?:\/\//i.test(raw)) {
    try {
      candidate = new URL(raw).searchParams.get("code") ?? "";
    } catch {
      return null;
    }
  }
  const code = candidate.trim().toUpperCase();
  return CODE_RE.test(code) ? code : null;
}

type TorchCapabilities = MediaTrackCapabilities & { torch?: boolean };

function stopVideoTracks(video: HTMLVideoElement | null) {
  const stream = video?.srcObject;
  if (stream && typeof (stream as MediaStream).getTracks === "function") {
    (stream as MediaStream).getTracks().forEach((track) => track.stop());
  }
  if (video) video.srcObject = null;
}

type Props = {
  onCode: (code: string) => void;
  onCancel: () => void;
  onCameraError: (message: string) => void;
};

export default function Scanner({ onCode, onCancel, onCameraError }: Props) {
  const [video, setVideo] = useState<HTMLVideoElement | null>(null);
  const [starting, setStarting] = useState(true);
  const [detected, setDetected] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [torchTrack, setTorchTrack] = useState<MediaStreamTrack | null>(null);
  const [torchOn, setTorchOn] = useState(false);

  const controlsRef = useRef<IScannerControls | null>(null);
  const onCodeRef = useRef(onCode);
  const onErrorRef = useRef(onCameraError);
  useEffect(() => {
    onCodeRef.current = onCode;
    onErrorRef.current = onCameraError;
  });

  const videoRef = useCallback((node: HTMLVideoElement | null) => setVideo(node), []);

  useEffect(() => {
    if (!video) return;
    let cancelled = false;
    let found = false;
    let noticeTimer: ReturnType<typeof setTimeout> | null = null;
    let doneTimer: ReturnType<typeof setTimeout> | null = null;

    const stopAll = () => {
      try {
        controlsRef.current?.stop();
      } catch {
        // ya detenido
      }
      controlsRef.current = null;
      stopVideoTracks(video);
    };

    async function start() {
      if (!navigator.mediaDevices?.getUserMedia) {
        onErrorRef.current("No pudimos acceder a la cámara. Revisa los permisos del navegador.");
        return;
      }
      try {
        const [{ BrowserQRCodeReader }, { BarcodeFormat, DecodeHintType }] = await Promise.all([
          import("@zxing/browser"),
          import("@zxing/library"),
        ]);
        if (cancelled || !video) return;

        const hints = new Map<HintType, unknown>();
        hints.set(DecodeHintType.POSSIBLE_FORMATS, [BarcodeFormat.QR_CODE]);
        hints.set(DecodeHintType.TRY_HARDER, true);
        const reader = new BrowserQRCodeReader(hints, {
          delayBetweenScanAttempts: 0,
          delayBetweenScanSuccess: 500,
        });

        const controls = await reader.decodeFromConstraints(
          {
            audio: false,
            video: {
              facingMode: { ideal: "environment" },
              width: { ideal: 1920 },
              height: { ideal: 1080 },
              frameRate: { ideal: 30 },
            },
          },
          video,
          (result) => {
            if (!result || found || cancelled) return;
            const code = extractRedeemCode(result.getText());
            if (!code) {
              setNotice("Ese QR no es de MonAvi. Apunta al QR del cliente.");
              if (noticeTimer) clearTimeout(noticeTimer);
              noticeTimer = setTimeout(() => setNotice(null), 2200);
              return;
            }
            found = true;
            setNotice(null);
            setDetected(true);
            try {
              navigator.vibrate?.(80);
            } catch {
              // sin vibracion
            }
            stopAll();
            doneTimer = setTimeout(() => onCodeRef.current(code), DETECTED_DELAY_MS);
          }
        );
        if (cancelled) {
          controls.stop();
          stopVideoTracks(video);
          return;
        }
        controlsRef.current = controls;
        setStarting(false);

        // Linterna: solo si la pista la ofrece.
        const stream = video.srcObject as MediaStream | null;
        const track = stream?.getVideoTracks?.()[0] ?? null;
        if (track && typeof track.getCapabilities === "function") {
          const caps = track.getCapabilities() as TorchCapabilities;
          if (caps.torch) setTorchTrack(track);
        }
      } catch (error) {
        console.error("escaner", error);
        if (!cancelled) {
          stopAll();
          onErrorRef.current("No pudimos acceder a la cámara. Revisa los permisos del navegador.");
        }
      }
    }

    void start();
    return () => {
      cancelled = true;
      if (noticeTimer) clearTimeout(noticeTimer);
      if (doneTimer) clearTimeout(doneTimer);
      stopAll();
    };
  }, [video]);

  async function toggleTorch() {
    if (!torchTrack) return;
    const next = !torchOn;
    try {
      await torchTrack.applyConstraints({ advanced: [{ torch: next } as MediaTrackConstraintSet] });
      setTorchOn(next);
    } catch {
      setTorchTrack(null);
    }
  }

  return (
    <div className="caja-scanner">
      <div className={`caja-viewfinder${detected ? " is-detected" : ""}`}>
        <video ref={videoRef} className="caja-video" muted playsInline autoPlay />
        <div className="caja-target" aria-hidden="true">
          <span className="caja-corner tl" />
          <span className="caja-corner tr" />
          <span className="caja-corner bl" />
          <span className="caja-corner br" />
          {!detected && <span className="caja-sweep" />}
        </div>
        {detected && <div className="caja-flash" aria-hidden="true" />}
        <div className="caja-scan-status" role="status" aria-live="polite">
          {starting ? "Abriendo la cámara…" : detected ? "¡Leído!" : notice ?? "Apunta al QR del cliente"}
        </div>
      </div>
      <div className="caja-scan-actions">
        <button type="button" className="caja-btn caja-btn-secondary" onClick={onCancel}>
          Cancelar
        </button>
        {torchTrack && (
          <button
            type="button"
            className={`caja-btn caja-btn-secondary${torchOn ? " is-on" : ""}`}
            aria-pressed={torchOn}
            onClick={toggleTorch}
          >
            {torchOn ? "Apagar linterna" : "Linterna"}
          </button>
        )}
      </div>
    </div>
  );
}
