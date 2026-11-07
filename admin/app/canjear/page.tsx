import type { Metadata } from "next";
import RedeemForm from "./RedeemForm";

// Pagina PUBLICA (sin clave del panel, ver PUBLIC_PATHS en proxy.ts) para
// que el cajero del comercio aliado valide el codigo de canje del cliente
// con el PIN de 6 digitos de su comercio. El QR de la app abre
// https://monavi.maday.app/canjear?code=XXXXXX con el codigo ya escrito.
export const metadata: Metadata = {
  title: "Validar canje — MonAvi",
  description: "Valida en caja el código de canje de un cliente de MonAvi con el PIN de tu comercio.",
  robots: { index: false, follow: false },
};

function normalizeCode(raw: string | string[] | undefined): string {
  const value = Array.isArray(raw) ? raw[0] : raw;
  return (value ?? "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 6);
}

export default async function CanjearPage({ searchParams }: { searchParams: Promise<{ code?: string | string[] }> }) {
  const params = await searchParams;
  const initialCode = normalizeCode(params.code);

  return (
    <div className="landing redeem-page">
      <header className="landing-nav">
        <a href="/canjear" className="landing-logo" style={{ color: "inherit" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="landing-logo-mark" src="/monavi-mark.svg" alt="" aria-hidden="true" />
          MonAvi
        </a>
        <span className="redeem-tag">Canje en caja</span>
      </header>

      <main className="redeem-main">
        <h1>Validar un canje</h1>
        <p className="redeem-help">
          El cliente te muestra un código de 6 letras y números en la app MonAvi. Escríbelo o escanea su QR con la cámara.
        </p>
        <RedeemForm initialCode={initialCode} />
      </main>

      <footer className="landing-footer">
        <span>© {new Date().getFullYear()} MonAvi · Panamá</span>
        <span>
          ¿Problemas con el PIN? <a href="mailto:hola@maday.app">hola@maday.app</a>
        </span>
      </footer>
    </div>
  );
}
