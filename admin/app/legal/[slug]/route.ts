import { readFileSync } from "node:fs";
import path from "node:path";

// Documentos legales publicos (admin/legal/<slug>.html). La app solo los
// enlaza: no se guardan en la base de datos ni en la app.
const SLUGS = [
  "guia-del-consumidor",
  "politica-de-compras",
  "cancelaciones-y-reembolsos",
  "ley-81",
  "proteccion-de-datos",
] as const;

export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams() {
  return SLUGS.map((slug) => ({ slug }));
}

export async function GET(_request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (!(SLUGS as readonly string[]).includes(slug)) {
    return new Response("No encontrado", { status: 404 });
  }
  const html = readFileSync(path.join(process.cwd(), "legal", `${slug}.html`), "utf8");
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}
