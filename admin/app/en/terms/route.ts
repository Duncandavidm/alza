import { readFileSync } from "node:fs";
import path from "node:path";

// Versión en inglés (1.1.0): admin/legal/terms.en.html. Si hay diferencias,
// manda la versión en español (/terms).
export const dynamic = "force-static";

const html = readFileSync(path.join(process.cwd(), "legal", "terms.en.html"), "utf8");

export function GET() {
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}
