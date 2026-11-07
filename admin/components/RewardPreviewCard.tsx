// Vista previa de como se ve un producto canjeable en la app de MonAvi:
// nombre del comercio (con su logo) arriba, la foto del producto grande
// (4:3) como protagonista, el producto con su valor en cashback (US$), y los
// botones "Cómo llegar" y "Canjear". Sin hooks: sirve en server y client.

import { formatCashback } from "@/lib/format";

type Props = {
  merchantName: string;
  logoUrl?: string | null;
  productName: string;
  photoUrl?: string | null;
  /// Valor en cashback en centavos (reward_items.points_cost; 1 punto = US$0.01).
  valueCents?: number | null;
  description?: string | null;
  hasMaps?: boolean;
  paused?: boolean;
};

export default function RewardPreviewCard({
  merchantName,
  logoUrl,
  productName,
  photoUrl,
  valueCents,
  description,
  hasMaps = true,
  paused,
}: Props) {
  return (
    <div className={`reward-preview${paused ? " is-paused" : ""}`}>
      <div className="reward-preview-header">
        {logoUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={logoUrl} alt="" className="reward-preview-logo" />
        ) : (
          <span className="reward-preview-logo placeholder">{merchantName.slice(0, 1).toUpperCase() || "?"}</span>
        )}
        <span className="reward-preview-merchant">{merchantName || "Nombre del comercio"}</span>
      </div>
      <div className="reward-preview-photo">
        {photoUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={photoUrl} alt={productName} />
        ) : (
          <span>Foto del producto (4:3)</span>
        )}
      </div>
      <div className="reward-preview-body">
        <span className="reward-preview-product">{productName || "Nombre del producto"}</span>
        <span className="reward-preview-points">
          {valueCents && valueCents > 0 ? formatCashback(valueCents) : "$—"}
        </span>
      </div>
      {description && <p className="reward-preview-description">{description}</p>}
      <div className="reward-preview-actions">
        <span className={`reward-preview-button outline${hasMaps ? "" : " disabled"}`}>Cómo llegar</span>
        <span className="reward-preview-button filled">Canjear</span>
      </div>
      {paused && <div className="reward-preview-paused">Pausado — no se ve en la app</div>}
    </div>
  );
}
