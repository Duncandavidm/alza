import { readFileSync } from "node:fs";
import path from "node:path";

// La version oficial vive en admin/legal/privacy.html (una sola fuente). Se lee
// al construir y se sirve como HTML estatico.
export const dynamic = "force-static";

const html = readFileSync(path.join(process.cwd(), "legal", "privacy.html"), "utf8");

export function GET() {
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}
