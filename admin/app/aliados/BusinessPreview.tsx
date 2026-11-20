"use client";

import { useMemo, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";

// Simulador: el comercio escribe su nombre y su producto y ve, en vivo,
// como aparece dentro de MonAvi (ficha en "Donde canjear" y el canje con
// codigo que el cliente muestra en caja). Imita el diseno real de la app.

type Currency = "cashback" | "puntos";

const PRESETS = [
  { emoji: "☕", category: "Cafetería", product: "Capuchino mediano", value: "3.50", currency: "cashback" as Currency },
  { emoji: "🥐", category: "Panadería", product: "Croissant de mantequilla", value: "2.25", currency: "cashback" as Currency },
  { emoji: "💈", category: "Barbería", product: "Perfilado de barba", value: "600", currency: "puntos" as Currency },
  { emoji: "🍦", category: "Heladería", product: "Helado de una bola", value: "2.50", currency: "cashback" as Currency },
  { emoji: "🏋️", category: "Gimnasio", product: "Pase de un día", value: "800", currency: "puntos" as Currency },
];

function initials(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  return (words[0]?.[0] ?? "T").toUpperCase() + (words[1]?.[0] ?? "").toUpperCase();
}

function makeCode(seed: string): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let h = 2166136261;
  for (const ch of seed) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
  let out = "";
  for (let i = 0; i < 6; i++) {
    h = Math.imul(h ^ (h >>> 13), 2246822519);
    out += alphabet[Math.abs(h) % alphabet.length];
  }
  return out;
}

/// QR ilustrativo (no escaneable): 13x13 con las tres esquinas tipicas.
function qrCells(seed: string): boolean[] {
  const n = 13;
  let h = 2166136261;
  for (const ch of seed) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
  const finder = (r: number, c: number) => {
    for (const [fr, fc] of [[0, 0], [0, n - 5], [n - 5, 0]]) {
      const y = r - fr, x = c - fc;
      if (y >= 0 && y < 5 && x >= 0 && x < 5) return y === 0 || y === 4 || x === 0 || x === 4 || (y === 2 && x === 2);
    }
    return null;
  };
  const cells: boolean[] = [];
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) {
    const f = finder(r, c);
    if (f !== null) { cells.push(f); continue; }
    h = Math.imul(h ^ (h >>> 15), 2246822519) ^ (r * 31 + c);
    cells.push((h >>> 7) % 100 < 46);
  }
  return cells;
}

export default function BusinessPreview() {
  const [name, setName] = useState("");
  const [presetIndex, setPresetIndex] = useState(0);
  const preset = PRESETS[presetIndex];
  const [product, setProduct] = useState(preset.product);
  const [value, setValue] = useState(preset.value);
  const [currency, setCurrency] = useState<Currency>(preset.currency);
  const [screen, setScreen] = useState<"ficha" | "canje">("ficha");

  const shownName = name.trim() || "Tu negocio";
  const shownProduct = product.trim() || "Tu producto";
  const numeric = Number(value.replace(",", "."));
  const priceLabel =
    currency === "cashback"
      ? `$${Number.isFinite(numeric) && numeric > 0 ? numeric.toFixed(2) : "0.00"}`
      : `${Number.isFinite(numeric) && numeric > 0 ? Math.round(numeric).toLocaleString("es-PA") : "0"} pts`;
  const code = useMemo(() => makeCode(shownName + shownProduct), [shownName, shownProduct]);

  function pickPreset(index: number) {
    const p = PRESETS[index];
    setPresetIndex(index);
    setProduct(p.product);
    setValue(p.value);
    setCurrency(p.currency);
  }

  return (
    <div className="al-sim">
      <div className="al-sim-controls">
        <label className="al-field">
          <span>Nombre de tu negocio</span>
          <input
            type="text"
            value={name}
            maxLength={40}
            placeholder="Ej. Café Casco Viejo"
            onChange={(e) => setName(e.target.value)}
          />
        </label>

        <div className="al-field">
          <span>Tipo de negocio</span>
          <div className="al-chips">
            {PRESETS.map((p, i) => (
              <button
                key={p.category}
                type="button"
                className={i === presetIndex ? "al-chip on" : "al-chip"}
                onClick={() => pickPreset(i)}
              >
                <span aria-hidden="true">{p.emoji}</span> {p.category}
              </button>
            ))}
          </div>
        </div>

        <label className="al-field">
          <span>Producto que regalas</span>
          <input type="text" value={product} maxLength={40} onChange={(e) => setProduct(e.target.value)} />
        </label>

        <div className="al-row2">
          <div className="al-field">
            <span>Se canjea con</span>
            <div className="al-seg">
              <button type="button" className={currency === "cashback" ? "on" : ""} onClick={() => { setCurrency("cashback"); setValue("3.50"); }}>
                Cashback
              </button>
              <button type="button" className={currency === "puntos" ? "on" : ""} onClick={() => { setCurrency("puntos"); setValue("600"); }}>
                Puntos
              </button>
            </div>
          </div>
          <label className="al-field">
            <span>{currency === "cashback" ? "Valor (US$)" : "Puntos"}</span>
            <input type="text" inputMode="decimal" value={value} maxLength={8} onChange={(e) => setValue(e.target.value.replace(/[^0-9.,]/g, ""))} />
          </label>
        </div>

        <div className="al-seg al-seg-wide" role="tablist" aria-label="Pantalla de la app">
          <button type="button" role="tab" aria-selected={screen === "ficha"} className={screen === "ficha" ? "on" : ""} onClick={() => setScreen("ficha")}>
            Tu ficha en la app
          </button>
          <button type="button" role="tab" aria-selected={screen === "canje"} className={screen === "canje" ? "on" : ""} onClick={() => setScreen("canje")}>
            El canje en caja
          </button>
        </div>
        <p className="al-note">Vista previa ilustrativa. Tu ficha real lleva tu logo y la foto de tu producto.</p>
      </div>

      <div className="al-phone" aria-live="polite">
        <div className="al-phone-notch" />
        <div className="al-phone-screen">
          <AnimatePresence mode="wait">
            {screen === "ficha" ? (
              <motion.div
                key="ficha"
                initial={{ opacity: 0, x: 30 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: -30 }}
                transition={{ duration: 0.28 }}
              >
                <div className="al-app-title">Dónde canjear</div>
                <div className="al-balances">
                  <div><small>Cashback</small><b>$5.58</b></div>
                  <div><small>Puntos</small><b>600 pts</b></div>
                </div>
                <motion.div className="al-mcard" layout>
                  <div className="al-mcard-head">
                    <motion.div key={presetIndex} className="al-mlogo" initial={{ scale: 0.6 }} animate={{ scale: 1 }}>
                      {name.trim() ? initials(name) : preset.emoji}
                    </motion.div>
                    <div className="al-mcard-info">
                      <b>{shownName}</b>
                      <small>{preset.category}</small>
                      <small>📍 Panamá</small>
                      <span className="al-tag">{currency === "cashback" ? "Canje con cashback" : "Canje con puntos"}</span>
                    </div>
                  </div>
                  <p className="al-mcard-line">1 premio desde {priceLabel} · ya te alcanza 🎉</p>
                  <div className="al-mcard-btns">
                    <span className="ghost">Cómo llegar</span>
                    <span className="solid" onClick={() => setScreen("canje")}>Ver premios</span>
                  </div>
                </motion.div>
                <div className="al-reward">
                  <div className="al-reward-photo" aria-hidden="true">{preset.emoji}</div>
                  <div>
                    <b>{shownProduct}</b>
                    <span className="al-price">{priceLabel}</span>
                  </div>
                </div>
              </motion.div>
            ) : (
              <motion.div
                key="canje"
                initial={{ opacity: 0, x: 30 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: -30 }}
                transition={{ duration: 0.28 }}
                className="al-redeem"
              >
                <div className="al-app-title">Tu canje</div>
                <div className="al-redeem-head">
                  <div className="al-reward-photo small" aria-hidden="true">{preset.emoji}</div>
                  <div>
                    <b>{shownName}</b>
                    <small>{shownProduct}</small>
                    <span className="al-price">{priceLabel}</span>
                  </div>
                </div>
                <div className="al-qr" aria-hidden="true">
                  {qrCells(code).map((on, i) => (
                    <i key={i} className={on ? "on" : ""} />
                  ))}
                </div>
                <small className="al-dim">Tu código</small>
                <div className="al-code">{code}</div>
                <span className="al-ready">Listo para usar</span>
                <p className="al-dim">Muéstralo en caja. El comercio lo valida con su PIN.</p>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
