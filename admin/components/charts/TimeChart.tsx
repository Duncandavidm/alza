"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { motion, useReducedMotion } from "framer-motion";

export type Point = { d: string; v: number };

type Props = {
  data: Point[];
  kind?: "area" | "bar";
  /// Texto del valor en el tooltip: "3 usuarios".
  unit?: [singular: string, plural: string];
  /// "dia" (21 nov) o "semana" (sem. del 17 nov).
  period?: "dia" | "semana";
  height?: number;
};

const MONTHS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
function shortDate(iso: string) {
  const [, m, d] = iso.split("-").map(Number);
  return `${d} ${MONTHS[(m || 1) - 1]}`;
}

/// Escala "bonita": 0 · mitad · tope redondeado.
function niceMax(max: number) {
  if (max <= 4) return 4;
  const pow = 10 ** Math.floor(Math.log10(max));
  const n = max / pow;
  const step = n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10;
  return step * pow;
}

function useWidth() {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new ResizeObserver(([entry]) => setWidth(Math.floor(entry.contentRect.width)));
    observer.observe(el);
    return () => observer.disconnect();
  }, []);
  return [ref, width] as const;
}

/// Serie de tiempo de un solo color (marca), con linea de 2px y area
/// suave, o columnas de punta redondeada. Al pasar el mouse muestra la
/// fecha y el valor. Una sola serie: el titulo de la tarjeta la nombra.
export default function TimeChart({ data, kind = "area", unit = ["", ""], period = "dia", height = 190 }: Props) {
  const [ref, width] = useWidth();
  const reduce = useReducedMotion();
  const [hover, setHover] = useState<number | null>(null);

  const max = niceMax(Math.max(...data.map((p) => p.v), 0));
  // El margen izquierdo crece con el largo del numero mas alto del eje.
  const pad = { top: 12, right: 12, bottom: 26, left: Math.max(30, max.toLocaleString("es-PA").length * 7 + 14) };
  const w = Math.max(width, 0);
  const innerW = Math.max(w - pad.left - pad.right, 10);
  const innerH = height - pad.top - pad.bottom;
  const n = data.length;

  const x = (i: number) => (kind === "bar" ? pad.left + (innerW / n) * (i + 0.5) : pad.left + (n <= 1 ? innerW / 2 : (innerW / (n - 1)) * i));
  const y = (v: number) => pad.top + innerH - (v / max) * innerH;

  const { line, area } = useMemo(() => {
    if (kind !== "area" || n === 0 || w === 0) return { line: "", area: "" };
    const pts = data.map((p, i) => `${x(i).toFixed(1)},${y(p.v).toFixed(1)}`);
    const l = `M${pts.join("L")}`;
    return { line: l, area: `${l}L${x(n - 1).toFixed(1)},${y(0)}L${x(0).toFixed(1)},${y(0)}Z` };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data, w, kind, max]);

  const barW = Math.min(24, Math.max(3, innerW / n - 2));

  function onMove(event: React.MouseEvent<SVGRectElement>) {
    const box = (event.currentTarget as SVGRectElement).getBoundingClientRect();
    const px = event.clientX - box.left;
    const i = kind === "bar" ? Math.floor((px / box.width) * n) : Math.round((px / box.width) * (n - 1));
    setHover(Math.max(0, Math.min(n - 1, i)));
  }

  const ticks = [0, max / 2, max];
  const hovered = hover !== null ? data[hover] : null;
  const label = (v: number) => `${v.toLocaleString("es-PA")} ${v === 1 ? unit[0] : unit[1]}`.trim();

  return (
    <div ref={ref} className="chart" style={{ height }}>
      {w > 0 && (
        <svg width={w} height={height} role="img" aria-label={`Gráfica: ${data.map((p) => `${shortDate(p.d)} ${p.v}`).join(", ")}`}>
          {ticks.map((t) => (
            <g key={t}>
              <line x1={pad.left} x2={w - pad.right} y1={y(t)} y2={y(t)} className="chart-grid" />
              <text x={pad.left - 8} y={y(t) + 4} textAnchor="end" className="chart-axis">
                {Number.isInteger(t) ? t.toLocaleString("es-PA") : t.toFixed(1)}
              </text>
            </g>
          ))}
          {[0, Math.floor((n - 1) / 2), n - 1].filter((v, i, arr) => arr.indexOf(v) === i && n > 0).map((i) => (
            <text key={i} x={x(i)} y={height - 6} textAnchor={i === 0 ? "start" : i === n - 1 ? "end" : "middle"} className="chart-axis">
              {period === "semana" ? `sem. ${shortDate(data[i].d)}` : shortDate(data[i].d)}
            </text>
          ))}

          {kind === "area" ? (
            <>
              <motion.path
                d={area}
                className="chart-area"
                initial={reduce ? false : { opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ duration: 0.8, delay: 0.3 }}
              />
              <motion.path
                d={line}
                className="chart-line"
                initial={reduce ? false : { pathLength: 0 }}
                animate={{ pathLength: 1 }}
                transition={{ duration: 1.1, ease: [0.22, 1, 0.36, 1] }}
              />
              {n > 0 && <circle cx={x(n - 1)} cy={y(data[n - 1].v)} r={4} className="chart-dot" />}
            </>
          ) : (
            data.map((p, i) => {
              const h = Math.max(0, y(0) - y(p.v));
              const r = Math.min(4, h, barW / 2);
              const x0 = x(i) - barW / 2;
              const y0 = y(p.v);
              // Punta redondeada (4px) y base recta.
              const path = h <= 0 ? "" :
                `M${x0},${y(0)}V${y0 + r}Q${x0},${y0} ${x0 + r},${y0}H${x0 + barW - r}Q${x0 + barW},${y0} ${x0 + barW},${y0 + r}V${y(0)}Z`;
              return (
                <motion.path
                  key={p.d}
                  d={path}
                  className={hover === i ? "chart-bar hover" : "chart-bar"}
                  style={{ transformOrigin: `${x(i)}px ${y(0)}px` }}
                  initial={reduce ? false : { scaleY: 0 }}
                  animate={{ scaleY: 1 }}
                  transition={{ duration: 0.55, delay: i * 0.02, ease: [0.22, 1, 0.36, 1] }}
                />
              );
            })
          )}

          {hovered && hover !== null && (
            <g pointerEvents="none">
              <line x1={x(hover)} x2={x(hover)} y1={pad.top} y2={y(0)} className="chart-crosshair" />
              {kind === "area" && <circle cx={x(hover)} cy={y(hovered.v)} r={5} className="chart-dot" />}
            </g>
          )}
          <rect
            x={pad.left}
            y={pad.top}
            width={innerW}
            height={innerH}
            fill="transparent"
            onMouseMove={onMove}
            onMouseLeave={() => setHover(null)}
          />
        </svg>
      )}
      {hovered && hover !== null && (
        <div
          className="chart-tooltip"
          style={{ left: Math.min(Math.max(x(hover), 70), w - 70), top: Math.max(y(hovered.v) - 52, 0) }}
        >
          <span>{period === "semana" ? `Semana del ${shortDate(hovered.d)}` : shortDate(hovered.d)}</span>
          <strong>{label(hovered.v)}</strong>
        </div>
      )}
    </div>
  );
}
