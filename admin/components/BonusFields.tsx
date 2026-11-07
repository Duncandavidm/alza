"use client";

import { useState } from "react";
import { BONUS_KINDS, BONUS_KIND_LABELS, type BonusKind, type RewardOptionGroup } from "@/lib/bonuses";

type Props = {
  defaults: {
    name: string;
    kind: BonusKind;
    amount: string;
    points: string;
    rewardItemId: string;
    message: string;
    expiresDays: string;
    notify: boolean;
  };
  rewardGroups: RewardOptionGroup[];
};

/// Datos del bono. Solo muestra los campos que aplican al tipo elegido.
export default function BonusFields({ defaults, rewardGroups }: Props) {
  const [kind, setKind] = useState<BonusKind>(defaults.kind);

  return (
    <div className="grid-form">
      <div className="field">
        <label htmlFor="bonus-name">Nombre interno</label>
        <input id="bonus-name" name="name" type="text" maxLength={80} defaultValue={defaults.name} placeholder="Regalo de noviembre" />
      </div>
      <div className="field">
        <label htmlFor="bonus-kind">Qué se regala</label>
        <select id="bonus-kind" name="kind" value={kind} onChange={(event) => setKind(event.target.value as BonusKind)}>
          {BONUS_KINDS.map((value) => (
            <option key={value} value={value}>
              {BONUS_KIND_LABELS[value]}
            </option>
          ))}
        </select>
      </div>

      {kind === "cashback" && (
        <div className="field">
          <label htmlFor="bonus-amount">Monto por persona (US$)</label>
          <input id="bonus-amount" name="amount" type="text" inputMode="decimal" defaultValue={defaults.amount} placeholder="1.00" />
        </div>
      )}
      {kind === "puntos" && (
        <div className="field">
          <label htmlFor="bonus-points">Puntos por persona</label>
          <input id="bonus-points" name="points" type="number" min={1} step={1} defaultValue={defaults.points} placeholder="100" />
        </div>
      )}
      {kind === "cupon" && (
        <>
          <div className="field wide">
            <label htmlFor="bonus-item">Producto gratis</label>
            <select id="bonus-item" name="reward_item_id" defaultValue={defaults.rewardItemId} style={{ width: "100%" }}>
              <option value="">Elige un producto…</option>
              {rewardGroups.map((group) => (
                <optgroup key={group.merchant} label={group.merchant}>
                  {group.items.map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.name} ({item.value})
                    </option>
                  ))}
                </optgroup>
              ))}
            </select>
            <small className="hint">
              Solo productos activos de comercios aliados. Cada persona recibe un código listo para mostrar en caja.
            </small>
          </div>
          <div className="field">
            <label htmlFor="bonus-expires">Vence en (días)</label>
            <input id="bonus-expires" name="expires_days" type="number" min={1} max={365} step={1} defaultValue={defaults.expiresDays} />
          </div>
        </>
      )}

      <div className="field wide">
        <label htmlFor="bonus-message">Lo que verá el cliente</label>
        <textarea
          id="bonus-message"
          name="message"
          rows={2}
          maxLength={240}
          defaultValue={defaults.message}
          placeholder="¡Gracias por usar MonAvi! Este regalo es para ti."
        />
        <small className="hint">Se usa como texto del aviso push. Si lo dejas vacío se usa un texto automático.</small>
      </div>
      <div className="field wide">
        <input type="hidden" name="notify_set" value="1" />
        <label style={{ display: "inline-flex", gap: 8, alignItems: "center", color: "var(--text)" }}>
          <input type="checkbox" name="notify" value="1" defaultChecked={defaults.notify} />
          Avisar por push a quienes lo reciban
        </label>
      </div>
    </div>
  );
}
