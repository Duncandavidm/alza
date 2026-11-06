"use client";

import { startTransition, useActionState, useEffect, useRef } from "react";

export type ActionState = { error?: string; message?: string };

type Props = {
  action: (prev: ActionState, formData: FormData) => Promise<ActionState>;
  children: React.ReactNode;
  className?: string;
  style?: React.CSSProperties;
  /// Pregunta de confirmacion (window.confirm) antes de enviar.
  confirm?: string;
  /// Limpia el formulario despues de un envio exitoso (formularios de
  /// "nuevo ..."). En formularios de edicion se deja en false.
  resetOnSuccess?: boolean;
  /// Etiqueta del boton de enviar; si se omite, el formulario trae el suyo.
  submitLabel?: string;
  submitClassName?: string;
  pendingLabel?: string;
  inline?: boolean;
  /// Se llama despues de un envio exitoso (p. ej. para limpiar estado local).
  onSuccess?: () => void;
};

/// Formulario generico para server actions que devuelven { error } o
/// { message }. Envia via startTransition (sin el reset automatico de
/// React 19) para que un error de validacion no borre lo que se escribio.
export default function ActionForm({
  action,
  children,
  className,
  style,
  confirm,
  resetOnSuccess,
  submitLabel,
  submitClassName,
  pendingLabel,
  inline,
  onSuccess,
}: Props) {
  const [state, formAction, isPending] = useActionState(action, {});
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (!state.message || state.error) return;
    if (resetOnSuccess) formRef.current?.reset();
    onSuccess?.();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state]);

  return (
    <form
      ref={formRef}
      className={className}
      style={inline ? { display: "inline-flex", gap: 8, alignItems: "center", flexWrap: "wrap", ...style } : style}
      onSubmit={(event) => {
        event.preventDefault();
        if (confirm && !window.confirm(confirm)) return;
        const formData = new FormData(event.currentTarget);
        startTransition(() => formAction(formData));
      }}
    >
      {children}
      {submitLabel && (
        <div className={inline ? undefined : "field"} style={inline ? undefined : { alignSelf: "end" }}>
          <button type="submit" className={submitClassName} disabled={isPending}>
            {isPending ? (pendingLabel ?? "Guardando…") : submitLabel}
          </button>
        </div>
      )}
      {state.error && (
        <p className="error" style={{ gridColumn: "1 / -1", margin: inline ? 0 : undefined }}>
          {state.error}
        </p>
      )}
      {state.message && !state.error && (
        <p className="success-text" style={{ gridColumn: "1 / -1", margin: inline ? 0 : undefined }}>
          {state.message}
        </p>
      )}
    </form>
  );
}
