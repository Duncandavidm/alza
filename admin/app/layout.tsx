import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "MonAvi Admin",
  description: "Panel interno para cashback, comercios aliados y bancos patrocinadores.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
