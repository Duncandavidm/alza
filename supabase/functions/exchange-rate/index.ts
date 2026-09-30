// Edge Function: exchange-rate
//
// Convierte un monto de una moneda a otra usando tasas del Banco Central
// Europeo via frankfurter.app (gratis, sin API key). Inspirado en
// "Paga en otra moneda y MonAi la convierte a la tuya al instante".
//
// NOTA: no se pudo probar contra un runtime Deno real en este entorno.
//
// No necesita secrets.

interface ExchangeRateResponse {
  amount: number;
  base: string;
  date: string;
  rates: Record<string, number>;
}

Deno.serve(async (req) => {
  try {
    const { from, to, amount } = await req.json();
    if (!from || !to || typeof amount !== "number") {
      return new Response(
        JSON.stringify({ error: "from, to y amount son requeridos" }),
        { status: 400 },
      );
    }

    if (from === to) {
      return new Response(JSON.stringify({ rate: 1, convertedAmount: amount }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const response = await fetch(
      `https://api.frankfurter.app/latest?amount=${amount}&from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`,
    );

    if (!response.ok) {
      throw new Error(`frankfurter.app error: ${response.status} ${await response.text()}`);
    }

    const data: ExchangeRateResponse = await response.json();
    const convertedAmount = data.rates[to];

    if (typeof convertedAmount !== "number") {
      return new Response(
        JSON.stringify({ error: `No hay tasa disponible para ${from} -> ${to}` }),
        { status: 422 },
      );
    }

    return new Response(
      JSON.stringify({
        rate: convertedAmount / amount,
        convertedAmount,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: String(error) }), { status: 500 });
  }
});
