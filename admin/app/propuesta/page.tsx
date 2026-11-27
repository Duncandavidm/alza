import type { Metadata } from "next";
import Proposal from "./Proposal";

// Propuesta comercial PUBLICA y generica para presentar a comercios
// ("Tu marca aqui"). En la reunion se personaliza en vivo: nombre, logo,
// color y oferta, y todas las pantallas de la app se actualizan. Nada se
// guarda ni se sube: el logo se ve solo en este navegador.
// Opcional: /propuesta?marca=Nombre&color=%23E4002B para abrirla ya
// personalizada.
export const metadata: Metadata = {
  title: "Propuesta para tu marca — MonAvi",
  description:
    "Cómo se vería tu marca dentro de MonAvi: descuentos, premios con cashback y campañas que llevan clientes a tu tienda. Sin costo de afiliación ni comisión.",
  robots: { index: false, follow: false },
};

export default async function PropuestaPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const pick = (key: string) => {
    const value = params[key];
    return (Array.isArray(value) ? value[0] : value)?.slice(0, 40) ?? "";
  };
  const color = pick("color");
  return <Proposal initialName={pick("marca")} initialColor={/^#[0-9a-fA-F]{6}$/.test(color) ? color : ""} />;
}
