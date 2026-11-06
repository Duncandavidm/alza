import { NextRequest, NextResponse } from "next/server";
import { SESSION_COOKIE_NAME, isValidSessionToken } from "./lib/auth";

// Paginas publicas de MonAvi (la app de consumo, no el panel admin) que
// viven en este mismo proyecto de Vercel a proposito: Apple exige una
// URL de politica de privacidad y de soporte antes de poder enviar la
// app a revision. Nunca deben quedar detras de la clave del panel.
// /aliados es la landing donde los comercios piden ser aliados; su
// formulario es una server action que hace POST a la misma ruta, asi que
// tambien queda publica (la accion valida todo y solo inserta en
// merchant_applications).
const PUBLIC_PATHS = ["/login", "/privacy", "/support", "/aliados"];

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  if (PUBLIC_PATHS.some((path) => pathname === path || pathname.startsWith(`${path}/`))) {
    return NextResponse.next();
  }

  const token = request.cookies.get(SESSION_COOKIE_NAME)?.value;
  const valid = await isValidSessionToken(token);
  if (!valid) {
    const loginUrl = new URL("/login", request.url);
    return NextResponse.redirect(loginUrl);
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
