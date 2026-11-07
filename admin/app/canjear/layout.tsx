import type { Metadata, Viewport } from "next";
import InstallPrompt from "./InstallPrompt";

// "MonAvi Caja": /canjear se instala como app (PWA) en el telefono o la
// tablet del comercio. El manifest y el service worker son publicos (ver
// PUBLIC_PATHS en proxy.ts).
export const metadata: Metadata = {
  manifest: "/canjear/manifest.webmanifest",
  applicationName: "MonAvi Caja",
  appleWebApp: { capable: true, title: "MonAvi Caja", statusBarStyle: "default" },
  icons: {
    icon: [{ url: "/caja/icon-192.png", sizes: "192x192", type: "image/png" }],
    apple: [{ url: "/caja/apple-touch-icon.png", sizes: "180x180" }],
  },
};

export const viewport: Viewport = {
  themeColor: "#027a64",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function CanjearLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      {children}
      <InstallPrompt />
    </>
  );
}
