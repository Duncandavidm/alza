import { NextRequest, NextResponse } from "next/server";
import { CSV_SECTIONS, fetchMarketInsights, parseDays, parseRuc, sectionToCsv } from "@/lib/insights";

// Protegida por proxy.ts (no esta en PUBLIC_PATHS): requiere la sesion
// del panel. Devuelve una seccion del estudio de mercado como CSV.
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const section = params.get("section") ?? "summary";
  if (!CSV_SECTIONS[section]) {
    return NextResponse.json({ error: "Sección inválida" }, { status: 400 });
  }
  const days = parseDays(params.get("days") ?? undefined);
  const ruc = parseRuc(params.get("ruc") ?? undefined);

  const result = await fetchMarketInsights(days, ruc);
  if (!result.data) {
    return NextResponse.json({ error: result.error ?? "Error" }, { status: 502 });
  }

  const csv = sectionToCsv(section, result.data) ?? "";
  const scope = ruc ? `ruc-${ruc.replace(/[^\w-]/g, "")}` : "general";
  const filename = `monavi-estudio-${section}-${scope}-${days}d.csv`;

  return new NextResponse(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${filename}"`,
      "Cache-Control": "no-store",
    },
  });
}
