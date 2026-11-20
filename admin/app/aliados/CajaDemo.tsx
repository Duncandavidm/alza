"use client";

import { useEffect, useState } from "react";
import { motion, useReducedMotion } from "framer-motion";

// Demo animada de la pagina de caja (monavi.maday.app/canjear): el cajero
// escribe el codigo del cliente, toca Validar y ve el producto a entregar.
const CODE = "K7Q2MX";

export default function CajaDemo() {
  const reduce = useReducedMotion();
  const [step, setStep] = useState(reduce ? CODE.length + 2 : 0);

  useEffect(() => {
    if (reduce) return;
    const delay = step < CODE.length ? 320 : step === CODE.length ? 700 : step === CODE.length + 1 ? 600 : 2600;
    const t = setTimeout(() => setStep((s) => (s >= CODE.length + 2 ? 0 : s + 1)), delay);
    return () => clearTimeout(t);
  }, [step, reduce]);

  const typed = CODE.slice(0, Math.min(step, CODE.length));
  const pressing = step === CODE.length + 1;
  const done = step >= CODE.length + 2;

  return (
    <div className="al-caja">
      <div className="al-caja-bar">
        <span /> <span /> <span />
        <em>monavi.maday.app/canjear</em>
      </div>
      <div className="al-caja-body">
        <div className="al-caja-title">Validar canje</div>
        <div className="al-caja-input">
          {typed}
          {!done && <span className="al-caret" />}
        </div>
        <motion.div className="al-caja-btn" animate={{ scale: pressing ? 0.94 : 1 }}>
          Validar
        </motion.div>
        <motion.div
          className="al-caja-ok"
          initial={false}
          animate={{ opacity: done ? 1 : 0, y: done ? 0 : 12 }}
          transition={{ duration: 0.3 }}
        >
          <div className="al-caja-check">✓</div>
          <div>
            <b>Canje válido</b>
            <small>Capuchino mediano · Ana R. · ••• 4821</small>
            <small>Entrégalo al cliente</small>
          </div>
        </motion.div>
      </div>
    </div>
  );
}
