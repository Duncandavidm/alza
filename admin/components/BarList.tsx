type Item = { label: string; v: number };

/// Lista de barras horizontales (un solo color) para repartos: tipo de
/// canje, genero, edad, comercios mas usados. Cada barra crece animada.
/// Con `total` muestra tambien el % de cada fila sobre ese total.
export default function BarList({ items, total, empty }: { items: Item[]; total?: number; empty?: string }) {
  if (items.length === 0 || items.every((item) => item.v === 0)) {
    return <p className="text-dim barlist-empty">{empty ?? "Todavía no hay datos."}</p>;
  }
  const max = Math.max(...items.map((item) => item.v), 1);
  return (
    <div className="funnel">
      {items.map((item, i) => {
        const pct = total && total > 0 ? Math.round((item.v / total) * 100) : null;
        const width = (item.v / max) * 100;
        return (
          <div key={item.label} className="funnel-row" style={{ ["--i" as string]: i } as React.CSSProperties}>
            <div className="funnel-label">
              <span>{item.label}</span>
              <strong>
                {item.v.toLocaleString("es-PA")}
                {pct !== null && <em>{pct}%</em>}
              </strong>
            </div>
            <div className="funnel-track">
              <div className="funnel-fill" style={{ width: `${Math.max(width, item.v > 0 ? 2 : 0)}%` }} />
            </div>
          </div>
        );
      })}
    </div>
  );
}
