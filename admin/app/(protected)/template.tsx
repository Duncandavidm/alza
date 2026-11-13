"use client";

import { motion, useReducedMotion } from "framer-motion";

/// Transicion suave al cambiar de seccion (se vuelve a montar en cada
/// navegacion). Respeta "Reducir movimiento" del sistema.
export default function Template({ children }: { children: React.ReactNode }) {
  const reduce = useReducedMotion();
  return (
    <motion.div
      initial={reduce ? false : { opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.22, ease: [0.22, 1, 0.36, 1] }}
    >
      {children}
    </motion.div>
  );
}
