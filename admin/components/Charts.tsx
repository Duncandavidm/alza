// Graficas simples con CSS (sin librerias) que comparten el estudio de
// mercado y el reporte de campañas de marcas. Componentes de servidor.

export type BarItem = { label: string; value: number; detail?: string; tag?: string };

export function Kpi({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="kpi">
      <div className="text-dim">{label}</div>
      <div className="kpi-value">{value}</div>
      {hint && <div className="text-dim kpi-hint">{hint}</div>}
    </div>
  );
}

export function BarList({ items, emptyText }: { items: BarItem[]; emptyText?: string }) {
  if (items.length === 0) {
    return <p className="text-dim">{emptyText ?? "Sin datos suficientes (ningún grupo llega a 5 personas)."}</p>;
  }
  const max = Math.max(...items.map((item) => item.value), 1);
  return (
    <ul className="bar-list">
      {items.map((item, index) => (
        <li key={`${item.label}-${index}`}>
          <div className="bar-list-label">
            <span>
              {item.label}
              {item.tag && <span className="badge active bar-tag">{item.tag}</span>}
            </span>
            <span className="text-dim">{item.detail}</span>
          </div>
          <div className="bar-track">
            <div className="bar-fill" style={{ width: `${Math.max((item.value / max) * 100, item.value > 0 ? 1.5 : 0)}%` }} />
          </div>
        </li>
      ))}
    </ul>
  );
}

/// Columnas verticales (una por hora, por dia del mes, ...). `highlight`
/// marca columnas con otro color (p. ej. los dias de quincena).
export function ColumnChart({
  items,
  ariaLabel,
  highlight,
}: {
  items: BarItem[];
  ariaLabel: string;
  highlight?: (item: BarItem, index: number) => boolean;
}) {
  const max = Math.max(...items.map((item) => item.value), 1);
  if (items.every((item) => item.value === 0)) {
    return <p className="text-dim">Sin datos suficientes.</p>;
  }
  return (
    <div
      className="column-chart"
      role="img"
      aria-label={ariaLabel}
      style={{ gridTemplateColumns: `repeat(${items.length}, minmax(0, 1fr))` }}
    >
      {items.map((item, index) => (
        <div key={`${item.label}-${index}`} className="column" title={item.detail}>
          <div className="column-bar-area">
            <div
              className={`column-bar${highlight?.(item, index) ? " highlight" : ""}`}
              style={{ height: `${(item.value / max) * 100}%` }}
            />
          </div>
          <span className="column-label">{item.label}</span>
        </div>
      ))}
    </div>
  );
}
