import { REWARD_CURRENCIES, REWARD_CURRENCY_LABELS, toRewardCurrency } from "@/lib/currency";

type Defaults = {
  brand?: string;
  name?: string;
  description?: string | null;
  image_url?: string | null;
  sponsor_contact?: string | null;
  keywords?: string[];
  merchant_rucs?: string[] | null;
  bonus_currency?: string | null;
  /// Ya convertidos para el input (US$ si es cashback, puntos si no).
  bonus_per_unit?: string;
  bonus_percent?: string;
  max_units_per_receipt?: number;
  fee_per_conversion?: string;
  budget_total?: string;
  starts_at?: string;
  ends_at?: string;
};

/// Campos de una campaña de marca (crear y editar).
export default function CampaignFieldsInputs({ defaults = {}, today }: { defaults?: Defaults; today: string }) {
  return (
    <>
      <div className="field">
        <label>Marca</label>
        <input type="text" name="brand" required maxLength={120} defaultValue={defaults.brand ?? ""} placeholder="Coca-Cola" />
      </div>
      <div className="field">
        <label>Nombre de la campaña</label>
        <input
          type="text"
          name="name"
          required
          maxLength={160}
          defaultValue={defaults.name ?? ""}
          placeholder="Doble cashback Coca-Cola noviembre"
        />
      </div>
      <div className="field wide">
        <label>Descripción (lo que ve el cliente)</label>
        <input
          type="text"
          name="description"
          maxLength={300}
          defaultValue={defaults.description ?? ""}
          placeholder="Gana el doble comprando Coca-Cola"
        />
      </div>
      <div className="field wide">
        <label>Palabras en la factura</label>
        <input
          type="text"
          name="keywords"
          required
          maxLength={2000}
          defaultValue={(defaults.keywords ?? []).join(", ")}
          placeholder="coca cola, coca-cola"
        />
        <small className="hint">
          Escríbelas como salen en la factura, ej: coca cola, coca-cola. Separadas por comas; no importan mayúsculas ni
          tildes. Una línea de la factura cuenta si contiene alguna de estas palabras.
        </small>
      </div>
      <div className="field wide">
        <label>Comercios (opcional)</label>
        <input
          type="text"
          name="merchant_rucs"
          maxLength={2000}
          defaultValue={(defaults.merchant_rucs ?? []).join(", ")}
          placeholder="RUC separados por comas"
        />
        <small className="hint">Vacío = en todos los comercios. Si pones RUC, solo cuentan las facturas de esos comercios.</small>
      </div>
      <div className="field">
        <label>Moneda del premio</label>
        <select name="bonus_currency" defaultValue={toRewardCurrency(defaults.bonus_currency ?? "puntos")} required>
          {REWARD_CURRENCIES.map((option) => (
            <option key={option} value={option}>
              {REWARD_CURRENCY_LABELS[option]}
            </option>
          ))}
        </select>
      </div>
      <div className="field">
        <label>Premio por unidad</label>
        <input
          type="text"
          name="bonus_per_unit"
          inputMode="decimal"
          maxLength={20}
          defaultValue={defaults.bonus_per_unit ?? ""}
          placeholder="ej. 50 pts o 0.25"
        />
        <small className="hint">En puntos, o en US$ si el premio es cashback. Opcional si pones extra por dólar.</small>
      </div>
      <div className="field">
        <label>Extra por cada dólar</label>
        <input
          type="text"
          name="bonus_percent"
          inputMode="decimal"
          maxLength={20}
          defaultValue={defaults.bonus_percent ?? ""}
          placeholder="ej. 1"
        />
        <small className="hint">
          Por cada dólar de esos productos: 1 = 1 punto o 1 centavo extra. El cashback normal es 1 centavo por dólar, así
          que 1 = el doble del cashback normal.
        </small>
      </div>
      <div className="field">
        <label>Máx. unidades por factura</label>
        <input
          type="number"
          name="max_units_per_receipt"
          min={1}
          max={1000}
          step={1}
          defaultValue={defaults.max_units_per_receipt ?? 5}
        />
        <small className="hint">Tope de unidades premiadas en una misma factura.</small>
      </div>
      <div className="field">
        <label>Tarifa por venta verificada (US$)</label>
        <input
          type="text"
          name="fee_per_conversion"
          inputMode="decimal"
          maxLength={20}
          defaultValue={defaults.fee_per_conversion ?? ""}
          placeholder="ej. 0.50"
        />
        <small className="hint">Lo que la marca le paga a MonAvi por cada factura que cumple la campaña.</small>
      </div>
      <div className="field">
        <label>Presupuesto de premios</label>
        <input
          type="text"
          name="budget_total"
          inputMode="decimal"
          maxLength={20}
          defaultValue={defaults.budget_total ?? ""}
          placeholder="ej. 100000 pts o 500"
        />
        <small className="hint">En puntos, o en US$ si es cashback. Vacío = sin tope. Al agotarse, la campaña se detiene.</small>
      </div>
      <div className="field">
        <label>Inicio</label>
        <input type="date" name="starts_at" required defaultValue={defaults.starts_at ?? today} />
        <small className="hint">Hora de Panamá, desde las 00:00.</small>
      </div>
      <div className="field">
        <label>Fin (opcional)</label>
        <input type="date" name="ends_at" defaultValue={defaults.ends_at ?? ""} />
        <small className="hint">Incluye todo ese día. Vacío = sin fecha de fin.</small>
      </div>
      <div className="field">
        <label>Contacto de la marca (interno)</label>
        <input
          type="text"
          name="sponsor_contact"
          maxLength={200}
          defaultValue={defaults.sponsor_contact ?? ""}
          placeholder="Nombre, correo o teléfono"
        />
      </div>
      <div className="field">
        <label>Imagen (enlace, opcional)</label>
        <input type="url" name="image_url" maxLength={600} defaultValue={defaults.image_url ?? ""} placeholder="https://…" />
      </div>
    </>
  );
}
