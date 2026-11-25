"use client";

import { useEffect, useState } from "react";
import ActionForm, { type ActionState } from "@/components/ActionForm";
import RewardPreviewCard from "@/components/RewardPreviewCard";
import { centsToDollarInput } from "@/lib/format";
import type { RewardCurrency } from "@/lib/currency";
import {
  BENEFIT_PERIODS,
  REWARD_TYPES,
  type RewardType,
  defaultRewardName,
  toBenefitPeriod,
  toRewardType,
} from "@/lib/reward-type";

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
  free_benefit?: boolean | null;
  per_user_limit?: number | null;
  per_user_period?: string | null;
  unlock_valid_days?: number | null;
  min_purchase?: number | string | null;
  funded_by?: string | null;
  available_from?: string | null;
  available_until?: string | null;
};

/// timestamptz → "2026-12-01" (fecha de Panama) para el input date.
function panamaDay(value: string | null | undefined): string {
  if (!value) return "";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "" : date.toLocaleDateString("en-CA", { timeZone: "America/Panama" });
}

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
  // "premio": cuesta cashback/puntos. "beneficio": descuento gratis por ser
  // de MonAvi (se desbloquea con la primera factura, con limite por persona).
  const [access, setAccess] = useState<"premio" | "beneficio">(item?.free_benefit ? "beneficio" : "premio");
  const isFree = access === "beneficio";
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
          setAccess("premio");
          setDiscountValue("");
          setDescription("");
          setRewardValue("");
          setPaused(false);
          setLocalPhoto(null);
        }}
      >
        <div className="field">
          <label>Cómo lo obtiene el cliente</label>
          <select
            name="access"
            value={access}
            onChange={(event) => {
              const next = event.target.value === "beneficio" ? "beneficio" : "premio";
              setAccess(next);
              if (next === "beneficio" && rewardType === "producto") setRewardType("porcentaje");
            }}
          >
            <option value="premio">Con cashback: el cliente lo desbloquea con su cashback</option>
            <option value="beneficio">Gratis: por ser de MonAvi (no cuesta cashback)</option>
          </select>
        </div>
        {isFree && (
          <>
            <div className="field">
              <label>Veces por persona</label>
              <input
                type="number"
                name="per_user_limit"
                min={1}
                max={100}
                step={1}
                inputMode="numeric"
                defaultValue={item?.per_user_limit ?? 1}
              />
            </div>
            <div className="field">
              <label>Cada cuánto se renueva</label>
              <select name="per_user_period" defaultValue={toBenefitPeriod(item?.per_user_period)}>
                {BENEFIT_PERIODS.map((period) => (
                  <option key={period.value} value={period.value}>
                    {period.label}
                  </option>
                ))}
              </select>
            </div>
            <p className="text-dim" style={{ gridColumn: "1 / -1", margin: 0 }}>
              El cliente lo desbloquea al escanear su primera factura fiscal, necesita correo verificado y en caja
              muestra un código que dura 15 minutos. No le cuesta cashback.
            </p>
          </>
        )}
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
        {!isFree && (
          <div className="field">
            <label>{isPoints ? "Puntos necesarios" : isDiscount ? "Se desbloquea con (US$ de cashback)" : "Valor en cashback (US$)"}</label>
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
        )}
        {!isFree && (
          <div className="field">
            <label>Días para usarlo después de desbloquearlo</label>
            <input
              type="number"
              name="unlock_valid_days"
              min={1}
              max={90}
              step={1}
              inputMode="numeric"
              defaultValue={item?.unlock_valid_days ?? 7}
            />
          </div>
        )}
        {isDiscount && (
          <div className="field">
            <label>Compra mínima (US$, opcional)</label>
            <input
              type="number"
              name="min_purchase"
              min={0.01}
              step={0.01}
              inputMode="decimal"
              placeholder="Sin mínimo"
              defaultValue={item?.min_purchase != null ? String(Number(item.min_purchase)) : ""}
            />
          </div>
        )}
        {rewardType === "monto" && (
          <div className="field">
            <label>Quién paga el bono</label>
            <select name="funded_by" defaultValue={item?.funded_by === "monavi" ? "monavi" : "comercio"}>
              <option value="comercio">El comercio (lo descuenta de la cuenta)</option>
              <option value="monavi">MonAvi (se le paga al comercio en la liquidación)</option>
            </select>
          </div>
        )}
        <div className="field">
          <label>Disponible desde (opcional)</label>
          <input type="date" name="available_from" defaultValue={panamaDay(item?.available_from)} />
        </div>
        <div className="field">
          <label>Disponible hasta (opcional)</label>
          <input type="date" name="available_until" defaultValue={panamaDay(item?.available_until)} />
        </div>
        {!isFree && isDiscount && (
          <p className="text-dim" style={{ gridColumn: "1 / -1", margin: 0 }}>
            El cliente lo desbloquea con su cashback y recibe un código para usarlo en caja dentro de esos días.
            Si no lo usa, el cashback se le devuelve. En la app verá «¡Desbloqueaste {autoName || "este beneficio"} en {merchantName}!».
          </p>
        )}
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
          value={isFree ? null : (isPoints ? Math.round(Number(rewardValue)) : Math.round(Number(rewardValue) * 100)) || null}
          isFree={isFree}
          currency={currency}
          description={description}
          hasMaps={hasMaps}
          paused={paused}
        />
      </div>
    </div>
  );
}
