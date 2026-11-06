"use client";

import { startTransition, useActionState, useEffect, useState } from "react";
import { MERCHANT_CATEGORIES } from "@/lib/merchant-categories";
import { submitMerchantApplication, type ApplicationFormState } from "./actions";

export default function ApplicationForm() {
  const [state, formAction, isPending] = useActionState(submitMerchantApplication, {} as ApplicationFormState);
  const [startedAt, setStartedAt] = useState("");

  useEffect(() => {
    setStartedAt(String(Date.now()));
  }, []);

  if (state.ok) {
    return (
      <div className="landing-success" role="status">
        <div className="landing-success-icon" aria-hidden="true">
          ✓
        </div>
        <h3>¡Gracias! Recibimos tu solicitud.</h3>
        <p>
          Nuestro equipo la revisa y te contacta en los próximos días hábiles por correo o teléfono para preparar juntos tu
          producto canjeable.
        </p>
      </div>
    );
  }

  return (
    <form
      className="landing-form"
      onSubmit={(event) => {
        event.preventDefault();
        const formData = new FormData(event.currentTarget);
        startTransition(() => formAction(formData));
      }}
    >
      {/* Honeypot: oculto para personas, los bots lo llenan. */}
      <div className="landing-hp" aria-hidden="true">
        <label htmlFor="website">Sitio web</label>
        <input id="website" name="website" type="text" tabIndex={-1} autoComplete="off" />
      </div>
      <input type="hidden" name="started_at" value={startedAt} />

      <div className="landing-field">
        <label htmlFor="business_name">Nombre del negocio *</label>
        <input id="business_name" name="business_name" type="text" required minLength={2} maxLength={120} autoComplete="organization" />
      </div>
      <div className="landing-field">
        <label htmlFor="ruc">RUC</label>
        <input id="ruc" name="ruc" type="text" maxLength={40} placeholder="Ej. 155612345-2-2021" />
      </div>
      <div className="landing-field">
        <label htmlFor="contact_name">Tu nombre *</label>
        <input id="contact_name" name="contact_name" type="text" required minLength={2} maxLength={120} autoComplete="name" />
      </div>
      <div className="landing-field">
        <label htmlFor="email">Correo electrónico *</label>
        <input id="email" name="email" type="email" required maxLength={160} autoComplete="email" />
      </div>
      <div className="landing-field">
        <label htmlFor="phone">Teléfono o WhatsApp</label>
        <input id="phone" name="phone" type="tel" maxLength={30} autoComplete="tel" placeholder="+507 6000-0000" />
      </div>
      <div className="landing-field">
        <label htmlFor="category">Categoría</label>
        <select id="category" name="category" defaultValue="">
          <option value="">Elige una categoría</option>
          {MERCHANT_CATEGORIES.map((category) => (
            <option key={category} value={category}>
              {category}
            </option>
          ))}
        </select>
      </div>
      <div className="landing-field wide">
        <label htmlFor="address">Dirección</label>
        <input id="address" name="address" type="text" maxLength={300} autoComplete="street-address" placeholder="Calle, local, barrio, ciudad" />
      </div>
      <div className="landing-field">
        <label htmlFor="maps_url">Enlace de Google Maps</label>
        <input id="maps_url" name="maps_url" type="url" maxLength={500} placeholder="https://maps.app.goo.gl/…" />
      </div>
      <div className="landing-field">
        <label htmlFor="instagram">Instagram</label>
        <input id="instagram" name="instagram" type="text" maxLength={60} placeholder="@tunegocio" />
      </div>
      <div className="landing-field wide">
        <label htmlFor="message">¿Qué producto te gustaría ofrecer? (opcional)</label>
        <textarea id="message" name="message" rows={4} maxLength={1000} placeholder="Ej. un café gratis, 2x1 en postres, un corte de cabello…" />
      </div>

      {state.error && (
        <p className="landing-error wide" role="alert">
          {state.error}
        </p>
      )}

      <div className="wide">
        <button type="submit" className="landing-button" disabled={isPending}>
          {isPending ? "Enviando…" : "Quiero ser aliado"}
        </button>
        <p className="landing-fineprint">
          Al enviar aceptas que te contactemos sobre el programa de aliados. Lee nuestra{" "}
          <a href="/privacy">política de privacidad</a>.
        </p>
      </div>
    </form>
  );
}
