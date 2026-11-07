import { NextRequest, NextResponse } from "next/server";
import {
  CSV_SECTIONS,
  fetchMarketInsights,
  hasFilters,
  parseDays,
  parseInsightFilters,
  parseRuc,
  sectionToCsv,
} from "@/lib/insights";

// Protegida por proxy.ts (no esta en PUBLIC_PATHS): requiere la sesion
// del panel. Devuelve una seccion del estudio de mercado como CSV, o el
// estudio completo como JSON (?format=json), con los mismos filtros de
// segmento que la pagina (gender, age, payment, product, category).
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;
  const format = params.get("format") === "json" ? "json" : "csv";
  const section = params.get("section") ?? "summary";
  if (format === "csv" && !CSV_SECTIONS[section]) {
    return NextResponse.json({ error: "Sección inválida" }, { status: 400 });
  }
  const days = parseDays(params.get("days") ?? undefined);
  const ruc = parseRuc(params.get("ruc") ?? undefined);
  const filters = parseInsightFilters((key) => params.get(key));

  const result = await fetchMarketInsights(days, ruc, filters);
  if (!result.data) {
    return NextResponse.json({ error: result.error ?? "Error" }, { status: 502 });
  }

  const scope = ruc ? `ruc-${ruc.replace(/[^\w-]/g, "")}` : "general";
  const segment = hasFilters(filters) ? "-segmento" : "";

  if (format === "json") {
    const filename = `monavi-estudio-${scope}${segment}-${days}d.json`;
    return new NextResponse(JSON.stringify(result.data, null, 2), {
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Content-Disposition": `attachment; filename="${filename}"`,
        "Cache-Control": "no-store",
      },
    });
  }

  const csv = sectionToCsv(section, result.data) ?? "";
  const filename = `monavi-estudio-${section}-${scope}${segment}-${days}d.csv`;

  return new NextResponse(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${filename}"`,
      "Cache-Control": "no-store",
    },
  });
}
