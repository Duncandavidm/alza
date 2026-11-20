import type { Metadata } from "next";
import { headers } from "next/headers";
import "./globals.css";

export const metadata: Metadata = {
  title: "MonAvi Admin",
  description: "Panel interno para cashback, comercios aliados y bancos patrocinadores.",
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  // Leer los headers hace que cada pagina se genere por peticion, asi Next
  // le pone a sus scripts el nonce de la CSP (ver proxy.ts).
  await headers();
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
