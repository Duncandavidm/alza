import type { Metadata } from "next";
import { cookies } from "next/headers";
import RedeemForm from "./RedeemForm";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { REDEEM_SESSION_COOKIE, readRedeemSessionToken } from "@/lib/redeem-session";

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

  // Turno abierto (cookie firmada): nombre del comercio para la cabecera.
  const session = readRedeemSessionToken((await cookies()).get(REDEEM_SESSION_COOKIE)?.value);
  let sessionMerchant: string | null = null;
  if (session) {
    try {
      const { data } = await supabaseAdmin()
        .from("partner_merchants")
        .select("name")
        .eq("id", session.merchant_id)
        .maybeSingle<{ name: string }>();
      sessionMerchant = data?.name ?? null;
    } catch {
      sessionMerchant = null;
    }
  }

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
          El cliente te muestra un QR o un código de 6 letras y números en la app MonAvi. Escanéalo con la cámara o
          escríbelo.
        </p>
        <RedeemForm initialCode={initialCode} initialSession={sessionMerchant ? { merchant: sessionMerchant } : null} />
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
