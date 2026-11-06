"use client";

export default function PrintButton({ label = "Imprimir / guardar PDF para el aliado" }: { label?: string }) {
  return (
    <button type="button" onClick={() => window.print()}>
      {label}
    </button>
  );
}
