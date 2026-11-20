import { readFileSync } from "node:fs";
import path from "node:path";

// Indice de documentos legales (admin/legal/index.html).
export const dynamic = "force-static";

const html = readFileSync(path.join(process.cwd(), "legal", "index.html"), "utf8");

export function GET() {
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}
