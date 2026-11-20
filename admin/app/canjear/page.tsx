import type { Metadata } from "next";
import { cookies } from "next/headers";
import CajaApp from "./CajaApp";
import { supabaseAdmin } from "@/lib/supabase-admin";
import { REDEEM_SESSION_COOKIE, readRedeemSessionToken } from "@/lib/redeem-session";

// "MonAvi Caja": pagina PUBLICA (sin clave del panel, ver PUBLIC_PATHS en
// proxy.ts) donde el cajero del comercio aliado inicia turno (RUC + PIN) y
// valida los canjes de los clientes (escanear QR, buscar cliente o escribir
// el codigo). El QR de la app abre
// https://monavi.maday.app/canjear?code=XXXXXX. El servidor lee la cookie
// del turno para decidir la pantalla inicial.
export const metadata: Metadata = {
  title: "MonAvi Caja",
  description: "Valida en caja los canjes de los clientes de MonAvi.",
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

  return <CajaApp initialCode={initialCode} initialMerchant={session ? (sessionMerchant ?? "tu comercio") : null} />;
}
