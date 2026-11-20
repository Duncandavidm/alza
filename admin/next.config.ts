import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  experimental: {
    // Logos y fotos de productos (bucket `rewards`, max 5 MB) se suben
    // por server action; el limite por defecto (1 MB) no alcanza.
    serverActions: {
      bodySizeLimit: "6mb",
    },
    // El proxy (auth) tambien lee el cuerpo de la peticion.
    proxyClientMaxBodySize: "6mb",
  },
};

export default nextConfig;
