import {
  SEGMENT_ACTIVITIES,
  SEGMENT_ACTIVITY_LABELS,
  SEGMENT_AGES,
  SEGMENT_DAYS,
  SEGMENT_GENDERS,
  SEGMENT_GENDER_LABELS,
  SEGMENT_PAYMENTS,
  SEGMENT_PAYMENT_LABELS,
  SEGMENT_PRESETS,
  type Segment,
} from "@/lib/segments";

type Props = {
  segment: Segment;
  merchants: { name: string; ruc: string }[];
  /// Botones de atajo ("Los que más usan la app", ...). Envian el
  /// formulario con ?preset=... y calculan el alcance al instante.
  showPresets?: boolean;
};

/// Campos del segmento (renderizados en el servidor). Van dentro de un
/// <form method="get">: "Calcular alcance" recarga la pagina con los
/// filtros en la URL y la pagina muestra segment_preview.
export default function SegmentFields({ segment, merchants, showPresets }: Props) {
  const knownRuc = !segment.merchant_ruc || merchants.some((m) => m.ruc === segment.merchant_ruc);
  return (
    <fieldset className="segment-fields">
      <legend>¿A quién?</legend>
      <p className="text-dim" style={{ marginTop: 0 }}>
        Deja todo en “Todos” para llegar a todas las personas que aceptaron recibir ofertas. Cada filtro achica el grupo.
      </p>
      {showPresets && (
        <div className="segment-presets">
          <span className="text-dim">Atajos:</span>
          {SEGMENT_PRESETS.map((preset) => (
            <button
              key={preset.activity}
              type="submit"
              name="preset"
              value={preset.activity}
              className={segment.activity === preset.activity ? "preset-chip active" : "preset-chip"}
            >
              {preset.label}
            </button>
          ))}
        </div>
      )}
      <div className="grid-form">
        <div className="field">
          <label htmlFor="seg-activity">Uso de la app</label>
          <select id="seg-activity" name="activity" defaultValue={segment.activity ?? ""}>
            <option value="">Todos</option>
            {SEGMENT_ACTIVITIES.map((value) => (
              <option key={value} value={value}>
                {SEGMENT_ACTIVITY_LABELS[value]}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="seg-days">Mirando los últimos</label>
          <select id="seg-days" name="days" defaultValue={String(segment.days ?? 30)}>
            {SEGMENT_DAYS.map((value) => (
              <option key={value} value={value}>
                {value} días
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="seg-gender">Género</label>
          <select id="seg-gender" name="gender" defaultValue={segment.gender ?? ""}>
            <option value="">Todos</option>
            {SEGMENT_GENDERS.map((value) => (
              <option key={value} value={value}>
                {SEGMENT_GENDER_LABELS[value]}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="seg-age">Edad</label>
          <select id="seg-age" name="age" defaultValue={segment.age_range ?? ""}>
            <option value="">Todas</option>
            {SEGMENT_AGES.map((value) => (
              <option key={value} value={value}>
                {value} años
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="seg-product">Compró un producto</label>
          <input
            id="seg-product"
            name="product"
            type="text"
            maxLength={60}
            defaultValue={segment.bought_product ?? ""}
            placeholder="ej. coca cola"
          />
          <small className="hint">Texto dentro del detalle de sus facturas (sin importar tildes).</small>
        </div>
        <div className="field">
          <label htmlFor="seg-ruc">Compró en el comercio</label>
          <select id="seg-ruc" name="ruc" defaultValue={segment.merchant_ruc ?? ""}>
            <option value="">Cualquiera</option>
            {!knownRuc && <option value={segment.merchant_ruc}>RUC {segment.merchant_ruc}</option>}
            {merchants.map((merchant) => (
              <option key={merchant.ruc} value={merchant.ruc}>
                {merchant.name}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="seg-payment">Forma de pago</label>
          <select id="seg-payment" name="payment" defaultValue={segment.payment ?? ""}>
            <option value="">Cualquiera</option>
            {SEGMENT_PAYMENTS.map((value) => (
              <option key={value} value={value}>
                {SEGMENT_PAYMENT_LABELS[value]}
              </option>
            ))}
          </select>
          <small className="hint">Según la factura. La factura no dice la marca de la tarjeta (Visa, Mastercard, Amex).</small>
        </div>
        <div className="field">
          <label htmlFor="seg-min-receipts">Mínimo de facturas</label>
          <input
            id="seg-min-receipts"
            name="min_receipts"
            type="number"
            min={0}
            max={1000}
            step={1}
            defaultValue={segment.min_receipts ?? ""}
            placeholder="0"
          />
        </div>
        <div className="field">
          <label htmlFor="seg-min-cashback">Cashback acumulado mínimo (US$)</label>
          <input
            id="seg-min-cashback"
            name="min_cashback"
            type="text"
            inputMode="decimal"
            defaultValue={segment.min_cashback ? (segment.min_cashback / 100).toFixed(2) : ""}
            placeholder="0.00"
          />
        </div>
        <div className="field">
          <label htmlFor="seg-min-savings">Ahorro mínimo en metas (US$)</label>
          <input id="seg-min-savings" name="min_savings" type="text" inputMode="decimal"
            defaultValue={segment.min_savings ?? ""} placeholder="ej. 500" />
        </div>
        <div className="field">
          <label htmlFor="seg-min-income">Ingreso mensual desde (US$)</label>
          <input id="seg-min-income" name="min_income" type="text" inputMode="decimal"
            defaultValue={segment.min_income ?? ""} placeholder="ej. 1000" />
          <small className="hint">Promedio de lo que registran como ingreso en el periodo elegido.</small>
        </div>
        <div className="field">
          <label htmlFor="seg-max-income">Ingreso mensual hasta (US$)</label>
          <input id="seg-max-income" name="max_income" type="text" inputMode="decimal"
            defaultValue={segment.max_income ?? ""} placeholder="ej. 3000" />
        </div>
      </div>
    </fieldset>
  );
}
