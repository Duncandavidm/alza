"use client";

import { useState } from "react";

export default function CopyButton({ value, label = "Copiar enlace" }: { value: string; label?: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      className="secondary"
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(value);
          setCopied(true);
          setTimeout(() => setCopied(false), 2000);
        } catch {
          window.prompt("Copia el enlace:", value);
        }
      }}
    >
      {copied ? "¡Copiado!" : label}
    </button>
  );
}
