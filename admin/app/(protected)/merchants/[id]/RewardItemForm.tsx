"use client";

import { useEffect, useState } from "react";
import ActionForm, { type ActionState } from "@/components/ActionForm";
import RewardPreviewCard from "@/components/RewardPreviewCard";

type Item = {
  name: string;
  description: string | null;
  photo_url: string | null;
  points_cost: number;
  status: "active" | "paused";
  sort_order: number;
};

type Props = {
  action: (prev: ActionState, formData: FormData) => Promise<ActionState>;
  merchantName: string;
  logoUrl: string | null;
  hasMaps: boolean;
  item?: Item;
  submitLabel: string;
};

/// Formulario de producto canjeable con vista previa en vivo (como se ve
/// en la app) que se actualiza mientras se escribe o se elige la foto.
export default function RewardItemForm({ action, merchantName, logoUrl, hasMaps, item, submitLabel }: Props) {
  const [name, setName] = useState(item?.name ?? "");
  const [description, setDescription] = useState(item?.description ?? "");
  const [points, setPoints] = useState(item ? String(item.points_cost) : "");
  const [paused, setPaused] = useState(item?.status === "paused");
  const [localPhoto, setLocalPhoto] = useState<string | null>(null);
  const [removePhoto, setRemovePhoto] = useState(false);

  useEffect(() => {
    return () => {
      if (localPhoto) URL.revokeObjectURL(localPhoto);
    };
  }, [localPhoto]);

  const photoUrl = localPhoto ?? (removePhoto ? null : (item?.photo_url ?? null));

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
          setDescription("");
          setPoints("");
          setPaused(false);
          setLocalPhoto(null);
        }}
      >
        <div className="field">
          <label>Producto</label>
          <input
            type="text"
            name="name"
            required
            maxLength={120}
            value={name}
            onChange={(event) => setName(event.target.value)}
            placeholder="Café latte grande"
          />
        </div>
        <div className="field">
          <label>Costo en puntos</label>
          <input
            type="number"
            name="points_cost"
            required
            min={1}
            step={1}
            value={points}
            onChange={(event) => setPoints(event.target.value)}
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
            defaultValue={item?.status ?? "active"}
            onChange={(event) => setPaused(event.target.value === "paused")}
          >
            <option value="active">Activo (visible en la app)</option>
            <option value="paused">Pausado</option>
          </select>
        </div>
        <div className="field" style={{ gridColumn: "1 / -1" }}>
          <label>Descripción (opcional)</label>
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
          productName={name}
          photoUrl={photoUrl}
          pointsCost={Number(points) || null}
          description={description}
          hasMaps={hasMaps}
          paused={paused}
        />
      </div>
    </div>
  );
}
