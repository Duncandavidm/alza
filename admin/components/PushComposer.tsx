"use client";

import { useState } from "react";
import { PUSH_BODY_MAX, PUSH_SCREENS, PUSH_SCREEN_LABELS, PUSH_TITLE_MAX, type PushScreen } from "@/lib/push";

type Props = { defaultTitle: string; defaultBody: string; defaultScreen: PushScreen };

/// Titulo, texto y pantalla de la notificacion, con una vista previa en
/// vivo de como se vera en la pantalla bloqueada del iPhone.
export default function PushComposer({ defaultTitle, defaultBody, defaultScreen }: Props) {
  const [title, setTitle] = useState(defaultTitle);
  const [body, setBody] = useState(defaultBody);

  return (
    <div className="reward-form-layout">
      <div>
        <div className="field">
          <label htmlFor="push-title">
            Título <span className="text-dim">({title.length}/{PUSH_TITLE_MAX})</span>
          </label>
          <input
            id="push-title"
            name="title"
            type="text"
            maxLength={PUSH_TITLE_MAX}
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            placeholder="¡Doble cashback este fin de semana!"
            style={{ width: "100%" }}
          />
        </div>
        <div className="field">
          <label htmlFor="push-body">
            Mensaje <span className="text-dim">({body.length}/{PUSH_BODY_MAX})</span>
          </label>
          <textarea
            id="push-body"
            name="body"
            rows={4}
            maxLength={PUSH_BODY_MAX}
            value={body}
            onChange={(event) => setBody(event.target.value)}
            placeholder="Escanea tus facturas de supermercado y gana el doble hasta el domingo."
            style={{ width: "100%" }}
          />
        </div>
        <div className="field">
          <label htmlFor="push-screen">Al tocarla abre</label>
          <select id="push-screen" name="screen" defaultValue={defaultScreen}>
            {PUSH_SCREENS.map((screen) => (
              <option key={screen} value={screen}>
                {PUSH_SCREEN_LABELS[screen]}
              </option>
            ))}
          </select>
        </div>
      </div>
      <PushPreview title={title} body={body} />
    </div>
  );
}

export function PushPreview({ title, body }: { title: string; body: string }) {
  return (
    <div className="push-phone" aria-label="Vista previa de la notificación">
      <div className="push-phone-time">9:41</div>
      <div className="push-card">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img className="push-card-icon" src="/monavi-mark.svg" alt="" aria-hidden="true" />
        <div className="push-card-text">
          <div className="push-card-head">
            <span className="push-card-app">MonAvi</span>
            <span className="push-card-when">ahora</span>
          </div>
          <div className="push-card-title">{title.trim() || "Título de la notificación"}</div>
          <div className="push-card-body">{body.trim() || "El mensaje aparece aquí."}</div>
        </div>
      </div>
    </div>
  );
}
