import { NextRequest, NextResponse } from "next/server";
import { SESSION_COOKIE_NAME, isValidSessionToken } from "./lib/auth";

// Paginas publicas de MonAvi (la app de consumo, no el panel admin) que
// viven en este mismo proyecto de Vercel a proposito: Apple exige una
// URL de politica de privacidad y de soporte antes de poder enviar la
// app a revision. Nunca deben quedar detras de la clave del panel.
// /aliados es la landing donde los comercios piden ser aliados; su
// formulario es una server action que hace POST a la misma ruta, asi que
// tambien queda publica (la accion valida todo y solo inserta en
// merchant_applications). /canjear es donde el cajero del comercio valida
// el codigo de canje del cliente con el PIN de su comercio: su server
// action solo llama a la RPC merchant_redeem (que verifica el PIN y
// limita los intentos fallidos por IP).
const PUBLIC_PATHS = ["/login", "/privacy", "/terms", "/support", "/aliados", "/canjear", "/canjear-sw.js", "/canjear-offline.html", "/email"];

const SUPABASE_ORIGIN = (() => {
  try {
    return new URL(process.env.SUPABASE_URL ?? "").origin;
  } catch {
    return "";
  }
})();

/// Content Security Policy con nonce: el navegador solo ejecuta los scripts
/// que trae el propio panel (Next les pone el nonce). Bloquea scripts
/// inyectados, iframes de otros sitios y formularios hacia otros dominios.
function contentSecurityPolicy(nonce: string): string {
  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'`,
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' data: blob: ${SUPABASE_ORIGIN}`.trim(),
    "font-src 'self' data:",
    `connect-src 'self' ${SUPABASE_ORIGIN}`.trim(),
    "media-src 'self' blob:",
    "worker-src 'self'",
    "manifest-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "upgrade-insecure-requests",
  ].join("; ");
}

function withSecurityHeaders(response: NextResponse, csp: string): NextResponse {
  response.headers.set("Content-Security-Policy", csp);
  response.headers.set("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload");
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("X-Frame-Options", "DENY");
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  // La camara solo la usa /canjear (lector de codigos del cajero).
  response.headers.set("Permissions-Policy", "camera=(self), microphone=(), geolocation=(), payment=()");
  response.headers.set("Cross-Origin-Opener-Policy", "same-origin");
  return response;
}

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const nonce = btoa(crypto.randomUUID());
  const csp = contentSecurityPolicy(nonce);
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("Content-Security-Policy", csp);
  const next = () => withSecurityHeaders(NextResponse.next({ request: { headers: requestHeaders } }), csp);

  if (PUBLIC_PATHS.some((path) => pathname === path || pathname.startsWith(`${path}/`))) {
    return next();
  }

  const token = request.cookies.get(SESSION_COOKIE_NAME)?.value;
  const valid = await isValidSessionToken(token);
  if (!valid) {
    const loginUrl = new URL("/login", request.url);
    return withSecurityHeaders(NextResponse.redirect(loginUrl), csp);
  }
  return next();
}

export const config = {
  // Las imagenes publicas (logo, icono) se sirven sin sesion: si no, la
  // landing /aliados mostraria el logo roto a quien no inicio sesion.
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|webp|ico)$).*)"],
};
