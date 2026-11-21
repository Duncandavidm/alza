"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { animate, useReducedMotion } from "framer-motion";
import Icon from "./icons";

type Props = {
  label: string;
  value: number;
  format?: "int" | "money" | "usd" | "pct";
  icon: string;
  /// Periodo anterior para el cambio en % ("vs. 30 días antes").
  previous?: number;
  deltaLabel?: string;
  /// Puntos para la mini grafica (ultimos dias).
  trend?: number[];
  hint?: string;
  href?: string;
  tone?: "default" | "warn";
};

function formatValue(value: number, format: Props["format"]) {
  if (format === "money") return "$" + (value / 100).toLocaleString("es-PA", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  if (format === "usd") return "$" + value.toLocaleString("es-PA", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  if (format === "pct") return `${Math.round(value)}%`;
  return Math.round(value).toLocaleString("es-PA");
}

function Sparkline({ points }: { points: number[] }) {
  if (points.length < 2) return null;
  const w = 96;
  const h = 30;
  const max = Math.max(...points, 1);
  const path = points
    .map((p, i) => `${i === 0 ? "M" : "L"}${((w - 4) / (points.length - 1)) * i + 2},${h - 3 - (p / max) * (h - 6)}`)
    .join("");
  const last = points[points.length - 1];
  return (
    <svg width={w} height={h} className="sparkline" aria-hidden="true">
      <path d={path} className="spark-line" />
      <circle cx={w - 2} cy={h - 3 - (last / max) * (h - 6)} r={3} className="spark-dot" />
    </svg>
  );
}

/// Indicador del dashboard: el numero sube animado desde 0, con el cambio
/// contra el periodo anterior y una mini grafica de tendencia.
export default function StatTile({ label, value, format = "int", icon, previous, deltaLabel, trend, hint, href, tone }: Props) {
  const reduce = useReducedMotion();
  const [shown, setShown] = useState(reduce ? value : 0);

  useEffect(() => {
    if (reduce) {
      setShown(value);
      return;
    }
    const controls = animate(0, value, { duration: 1.1, ease: [0.22, 1, 0.36, 1], onUpdate: setShown });
    return () => controls.stop();
  }, [value, reduce]);

  let delta: { text: string; up: boolean } | null = null;
  if (previous !== undefined) {
    if (previous === 0 && value > 0) delta = { text: "Nuevo", up: true };
    else if (previous > 0) {
      const pct = Math.round(((value - previous) / previous) * 100);
      delta = { text: `${pct > 0 ? "+" : ""}${pct}%`, up: pct >= 0 };
    }
  }

  const body = (
    <>
      <div className="tile-top">
        <span className="tile-icon">
          <Icon name={icon} size={18} />
        </span>
        <span className="tile-label">{label}</span>
      </div>
      <div className="tile-value">{formatValue(shown, format)}</div>
      <div className="tile-bottom">
        {delta ? (
          <span className={delta.up ? "tile-delta up" : "tile-delta down"}>
            <Icon name={delta.up ? "arrowUp" : "arrowDown"} size={13} />
            {delta.text}
            {deltaLabel && <em>{deltaLabel}</em>}
          </span>
        ) : (
          <span className="tile-hint">{hint}</span>
        )}
        {trend && <Sparkline points={trend} />}
      </div>
    </>
  );

  const className = tone === "warn" ? "tile warn" : "tile";
  return href ? (
    <Link href={href} className={`${className} link`}>
      {body}
    </Link>
  ) : (
    <div className={className}>{body}</div>
  );
}
