"use client";

import { useEffect, useState } from "react";
import ActionForm, { type ActionState } from "@/components/ActionForm";
import RewardPreviewCard from "@/components/RewardPreviewCard";
import { centsToDollarInput } from "@/lib/format";
import type { RewardCurrency } from "@/lib/currency";
import { REWARD_TYPES, type RewardType, defaultRewardName, toRewardType } from "@/lib/reward-type";

type Item = {
  name: string;
  description: string | null;
  photo_url: string | null;
  points_cost: number;
  status: "active" | "paused" | "agotado";
  sort_order: number;
  reward_type?: string | null;
  discount_value?: number | string | null;
  max_redemptions?: number | null;
};

type Props = {
  action: (prev: ActionState, formData: FormData) => Promise<ActionState>;
  merchantName: string;
  logoUrl: string | null;
  hasMaps: boolean;
  /// Moneda del comercio: solo cambia la etiqueta y el input; el servidor
  /// vuelve a leerla de la base para decidir la conversion.
  currency: RewardCurrency;
  item?: Item;
  submitLabel: string;
};

/// Formulario de producto canjeable con vista previa en vivo (como se ve
/// en la app) que se actualiza mientras se escribe o se elige la foto.
export default function RewardItemForm({ action, merchantName, logoUrl, hasMaps, currency, item, submitLabel }: Props) {
  const isPoints = currency === "puntos";
  const initialType = toRewardType(item?.reward_type);
  const initialDiscount = item?.discount_value != null ? String(Number(item.discount_value)) : "";
  const [rewardType, setRewardType] = useState<RewardType>(initialType);
  const [discountValue, setDiscountValue] = useState(initialDiscount);
  // Si el nombre guardado es el automatico ("10% de descuento"), se deja
  // vacio para que siga al valor cuando se edite.
  const [name, setName] = useState(
    item && item.name !== defaultRewardName(initialType, Number(initialDiscount)) ? item.name : ""
  );
  const [description, setDescription] = useState(item?.description ?? "");
  // Cashback: US$ (ej. "3.50"), el servidor lo guarda en centavos.
  // Puntos: entero (ej. "150"), se guarda tal cual.
  const [rewardValue, setRewardValue] = useState(
    item ? (isPoints ? String(item.points_cost) : centsToDollarInput(item.points_cost)) : ""
  );
  const [paused, setPaused] = useState(item?.status === "paused");
  const [localPhoto, setLocalPhoto] = useState<string | null>(null);
  const [removePhoto, setRemovePhoto] = useState(false);

  useEffect(() => {
    return () => {
      if (localPhoto) URL.revokeObjectURL(localPhoto);
    };
  }, [localPhoto]);

  const photoUrl = localPhoto ?? (removePhoto ? null : (item?.photo_url ?? null));
  const isDiscount = rewardType !== "producto";
  const autoName = defaultRewardName(rewardType, Number(discountValue));

  return (
    <div className="reward-form-layout">
      <ActionForm
        action={action}
        className="grid-form"
        submitLabel={submitLabel}
        resetOnSuccess={!item}
        onSuccess={() => {
          if (item) return;
          setName("");
          setRewardType("producto");
          setDiscountValue("");
          setDescription("");
          setRewardValue("");
          setPaused(false);
          setLocalPhoto(null);
        }}
      >
        <div className="field">
          <label>Qué se canjea</label>
          <select
            name="reward_type"
            value={rewardType}
            onChange={(event) => setRewardType(toRewardType(event.target.value))}
          >
            {REWARD_TYPES.map((type) => (
              <option key={type.value} value={type.value}>
                {type.label}
              </option>
            ))}
          </select>
        </div>
        {isDiscount && (
          <div className="field">
            <label>{rewardType === "porcentaje" ? "Descuento (%)" : "Valor del cupón (US$)"}</label>
            <input
              type="number"
              name="discount_value"
              required
              min={rewardType === "porcentaje" ? 1 : 0.01}
              max={rewardType === "porcentaje" ? 100 : undefined}
              step={rewardType === "porcentaje" ? 1 : 0.01}
              inputMode="decimal"
              placeholder={rewardType === "porcentaje" ? "10" : "20"}
              value={discountValue}
              onChange={(event) => setDiscountValue(event.target.value)}
            />
          </div>
        )}
        <div className="field">
          <label>{isDiscount ? "Nombre (opcional)" : "Producto"}</label>
          <input
            type="text"
            name="name"
            required={!isDiscount}
            maxLength={120}
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder={isDiscount ? autoName || (rewardType === "porcentaje" ? "10% de descuento" : "Cupón de $20") : "Café latte grande"}
          />
        </div>
        <div className="field">
          <label>{isPoints ? "Puntos necesarios" : "Valor en cashback (US$)"}</label>
          <input
            type="number"
            name="reward_value"
            required
            min={isPoints ? 1 : 0.01}
            step={isPoints ? 1 : 0.01}
            inputMode={isPoints ? "numeric" : "decimal"}
            placeholder={isPoints ? "150" : "3.50"}
            value={rewardValue}
            onChange={(event) => setRewardValue(event.target.value)}
          />
        </div>
        <div className="field">
          <label>Límite de canjes (vacío = sin límite)</label>
          <input
            type="number"
            name="max_redemptions"
            min={1}
            step={1}
            inputMode="numeric"
            placeholder="Sin límite"
            defaultValue={item?.max_redemptions ?? ""}
          />
        </div>
        <div className="field">
          <label>Orden (menor primero)</label>
          <input type="number" name="sort_order" step={1} defaultValue={item?.sort_order ?? 0} />
        </div>
        <div className="field">
          <label>Estado</label>
          <select
            name="status"
            defaultValue={item?.status === "paused" ? "paused" : "active"}
            onChange={(event) => setPaused(event.target.value === "paused")}
          >
            <option value="active">Activo (visible en la app)</option>
            <option value="paused">Pausado</option>
          </select>
        </div>
        <div className="field" style={{ gridColumn: "1 / -1" }}>
          <label>
            Descripción (opcional){isDiscount ? " — condiciones, ej. “En compras desde $50. No acumulable.”" : ""}
          </label>
          <textarea
            name="description"
            maxLength={500}
            rows={2}
            value={description}
            onChange={(event) => setDescription(event.target.value)}
            style={{ width: "100%" }}
          />
        </div>
        <div className="field" style={{ gridColumn: "1 / -1" }}>
          <label>Foto del producto (JPG, PNG o WebP, máx. 5 MB — idealmente horizontal 4:3)</label>
          <input
            type="file"
            name="photo"
            accept="image/jpeg,image/png,image/webp"
            onChange={(event) => {
              const file = event.target.files?.[0];
              setLocalPhoto(file ? URL.createObjectURL(file) : null);
            }}
          />
          {item?.photo_url && (
            <label style={{ marginTop: 6, display: "flex", gap: 6, alignItems: "center" }}>
              <input
                type="checkbox"
                name="remove_photo"
                checked={removePhoto}
                onChange={(event) => setRemovePhoto(event.target.checked)}
              />{" "}
              Quitar foto actual
            </label>
          )}
        </div>
      </ActionForm>
      <div>
        <div className="text-dim" style={{ marginBottom: 6 }}>
          Vista previa en la app
        </div>
        <RewardPreviewCard
          merchantName={merchantName}
          logoUrl={logoUrl}
          productName={name || autoName}
          photoUrl={photoUrl}
          value={(isPoints ? Math.round(Number(rewardValue)) : Math.round(Number(rewardValue) * 100)) || null}
          currency={currency}
          description={description}
          hasMaps={hasMaps}
          paused={paused}
        />
      </div>
    </div>
  );
}
