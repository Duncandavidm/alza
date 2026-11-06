import { MERCHANT_CATEGORIES } from "@/lib/merchant-categories";

type Defaults = {
  name?: string | null;
  ruc?: string | null;
  category?: string | null;
  address?: string | null;
  maps_url?: string | null;
  logo_url?: string | null;
};

/// Campos de la "ficha" del comercio aliado (crear y editar).
export default function MerchantFieldsInputs({ defaults = {} }: { defaults?: Defaults }) {
  const category = defaults.category ?? "";
  const isKnownCategory = (MERCHANT_CATEGORIES as readonly string[]).includes(category);

  return (
    <>
      <div className="field">
        <label>Nombre del comercio</label>
        <input type="text" name="name" required maxLength={120} defaultValue={defaults.name ?? ""} />
      </div>
      <div className="field">
        <label>RUC</label>
        <input type="text" name="ruc" required maxLength={40} defaultValue={defaults.ruc ?? ""} />
      </div>
      <div className="field">
        <label>Categoría</label>
        <select name="category" defaultValue={category}>
          <option value="">Sin categoría</option>
          {!isKnownCategory && category && <option value={category}>{category}</option>}
          {MERCHANT_CATEGORIES.map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
        </select>
      </div>
      <div className="field">
        <label>Dirección</label>
        <input type="text" name="address" maxLength={300} defaultValue={defaults.address ?? ""} placeholder="Calle 50, Obarrio…" />
      </div>
      <div className="field">
        <label>Enlace de Google Maps (“Cómo llegar”)</label>
        <input
          type="url"
          name="maps_url"
          maxLength={500}
          defaultValue={defaults.maps_url ?? ""}
          placeholder="https://maps.app.goo.gl/…"
        />
      </div>
      <div className="field">
        <label>Logo (JPG, PNG o WebP, máx. 5 MB)</label>
        <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
          {defaults.logo_url && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={defaults.logo_url} alt="Logo actual" className="thumb round" />
          )}
          <input type="file" name="logo" accept="image/jpeg,image/png,image/webp" />
        </div>
        {defaults.logo_url && (
          <label style={{ marginTop: 6, display: "flex", gap: 6, alignItems: "center" }}>
            <input type="checkbox" name="remove_logo" /> Quitar logo actual
          </label>
        )}
      </div>
    </>
  );
}
