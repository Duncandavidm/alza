"use client";

import { useMemo, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";

// Simulador: el comercio escribe su nombre y su producto y ve, en vivo,
// como aparece dentro de MonAvi (ficha en "Donde canjear" y el codigo que
// el cliente muestra en caja). Imita el diseno real de la app.
//
// Dos formas de estar en MonAvi: un premio que el cliente canjea con su
// cashback, o un descuento por ser de MonAvi (ej. 20%, 1 vez por semana).

type Offer = "premio" | "descuento";

const PRESETS = [
  { emoji: "☕", category: "Cafetería", product: "Capuchino mediano", value: "3.50", offer: "premio" as Offer },
  { emoji: "🥐", category: "Panadería", product: "En toda la panadería", value: "15", offer: "descuento" as Offer },
  { emoji: "💈", category: "Barbería", product: "En cortes de cabello", value: "20", offer: "descuento" as Offer },
  { emoji: "🍦", category: "Heladería", product: "Helado de una bola", value: "2.50", offer: "premio" as Offer },
  { emoji: "🏋️", category: "Gimnasio", product: "En la mensualidad", value: "10", offer: "descuento" as Offer },
];

const DEFAULTS: Record<Offer, { product: string; value: string }> = {
  premio: { product: "Capuchino mediano", value: "3.50" },
  descuento: { product: "En toda la tienda", value: "20" },
};

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
  const [offer, setOffer] = useState<Offer>(preset.offer);
  const [screen, setScreen] = useState<"ficha" | "canje">("ficha");

  const shownName = name.trim() || "Tu negocio";
  const shownProduct = product.trim() || "Tu producto";
  const numeric = Number(value.replace(",", "."));
  const isDiscount = offer === "descuento";
  const percent = Number.isFinite(numeric) && numeric > 0 ? Math.min(100, Math.round(numeric)) : 0;
  const priceLabel = `$${Number.isFinite(numeric) && numeric > 0 ? numeric.toFixed(2) : "0.00"}`;
  const dealTitle = `${percent}% de descuento`;
  const itemTitle = isDiscount ? dealTitle : shownProduct;
  const code = useMemo(() => makeCode(shownName + shownProduct), [shownName, shownProduct]);

  function pickPreset(index: number) {
    const p = PRESETS[index];
    setPresetIndex(index);
    setProduct(p.product);
    setValue(p.value);
    setOffer(p.offer);
  }

  function pickOffer(next: Offer) {
    if (next === offer) return;
    setOffer(next);
    setProduct(DEFAULTS[next].product);
    setValue(DEFAULTS[next].value);
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
          <span>{isDiscount ? "En qué aplica" : "Producto que regalas"}</span>
          <input type="text" value={product} maxLength={40} onChange={(e) => setProduct(e.target.value)} />
        </label>

        <div className="al-row2">
          <div className="al-field">
            <span>Qué ofreces</span>
            <div className="al-seg">
              <button type="button" className={offer === "premio" ? "on" : ""} onClick={() => pickOffer("premio")}>
                Premio
              </button>
              <button type="button" className={offer === "descuento" ? "on" : ""} onClick={() => pickOffer("descuento")}>
                Descuento
              </button>
            </div>
          </div>
          <label className="al-field">
            <span>{isDiscount ? "Descuento (%)" : "Valor en cashback (US$)"}</span>
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
        <p className="al-note">
          {isDiscount
            ? "Descuento por ser de MonAvi: tú decides cada cuánto lo puede usar cada persona (por ejemplo, 1 vez por semana)."
            : "Premio con cashback: el cliente lo canjea con el cashback que gana con sus facturas."}{" "}
          Vista previa ilustrativa: tu ficha real lleva tu logo y la foto de tu producto.
        </p>
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
                <div className="al-balances single">
                  <div><small>Tu cashback</small><b>$5.58</b></div>
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
                      <span className="al-tag">{isDiscount ? "Descuento por ser de MonAvi" : "Canje con cashback"}</span>
                    </div>
                  </div>
                  <p className="al-mcard-line">
                    {isDiscount ? `${dealTitle} · 1 vez por semana` : `1 premio desde ${priceLabel} · ya te alcanza 🎉`}
                  </p>
                  <div className="al-mcard-btns">
                    <span className="ghost">Cómo llegar</span>
                    <span className="solid" onClick={() => setScreen("canje")}>{isDiscount ? "Ver descuentos" : "Ver premios"}</span>
                  </div>
                </motion.div>
                <div className="al-reward">
                  <div className="al-reward-photo" aria-hidden="true">{preset.emoji}</div>
                  <div>
                    <b>{itemTitle}</b>
                    {isDiscount ? <small className="al-dim">{shownProduct}</small> : <span className="al-price">{priceLabel}</span>}
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
                <div className="al-app-title">{isDiscount ? "Tu descuento" : "Tu canje"}</div>
                <div className="al-redeem-head">
                  <div className="al-reward-photo small" aria-hidden="true">{preset.emoji}</div>
                  <div>
                    <b>{shownName}</b>
                    <small>{itemTitle}</small>
                    {isDiscount ? <small>{shownProduct}</small> : <span className="al-price">{priceLabel}</span>}
                  </div>
                </div>
                <div className="al-qr" aria-hidden="true">
                  {qrCells(code).map((on, i) => (
                    <i key={i} className={on ? "on" : ""} />
                  ))}
                </div>
                <small className="al-dim">Tu código</small>
                <div className="al-code">{code}</div>
                <span className="al-ready">{isDiscount ? "Vence en 14:59" : "Listo para usar"}</span>
                <p className="al-dim">
                  {isDiscount
                    ? "Muéstralo en caja. El comercio lo aplica con su PIN y le recuerda pedir su factura fiscal."
                    : "Muéstralo en caja. El comercio lo valida con su PIN."}
                </p>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
