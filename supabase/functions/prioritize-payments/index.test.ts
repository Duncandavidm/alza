// Pruebas unitarias de computeRanking/liquidityNote/fallbackReason —
// la parte 100% deterministica de prioritize-payments (nunca llama a
// Claude ni a la red). Corre con `deno test` dentro de esta carpeta.
//
// NOTA para quien lea esto despues: no se pudo correr `deno test` en el
// entorno donde se escribieron (sin runtime Deno disponible). La misma
// logica (formulas identicas, copiadas a mano) se valido aparte bajo
// Node con los mismos 9 casos antes de integrarla a index.ts — pero eso
// no reemplaza correr este archivo de verdad. Antes de confiar en este
// cambio, correr `deno test` aqui mismo y confirmar que pasa.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  computeRanking,
  fallbackReason,
  isBillOverdue,
  liquidityNote,
  proximityScore,
  tierBase,
} from "./index.ts";

const TODAY = new Date("2026-10-12T12:00:00Z");

function bill(id: string, dueDate: string, priority: string, isOverdue: boolean) {
  return { id, due_date: dueDate, priority, name: `bill-${id}` };
}

function debt(id: string, opts: { dueDate?: string | null; isOverdue?: boolean; rate?: number | null; balance?: number } = {}) {
  return {
    id,
    due_date: opts.dueDate ?? null,
    is_overdue: opts.isOverdue ?? false,
    interest_rate_monthly: opts.rate ?? null,
    balance: opts.balance ?? 0,
    creditor: `debt-${id}`,
  };
}

Deno.test("tierBase: vencido siempre gana, sin importar cuantos dias", () => {
  assert(tierBase(-1, true) > tierBase(7, false));
  assert(tierBase(-30, true) === tierBase(-1, true)); // mismo tier, el desempate va en proximityScore
});

Deno.test("proximityScore: mas vencido = mas urgente (desempate correcto)", () => {
  const masVencido = proximityScore(-10, true);
  const pocoVencido = proximityScore(-1, true);
  assert(masVencido > pocoVencido, "una cuenta vencida hace 10 dias debe pesar mas que una vencida hace 1 dia");
});

Deno.test("proximityScore: mas cerca de vencer (futuro) = mas urgente", () => {
  const manana = proximityScore(1, false);
  const en10dias = proximityScore(10, false);
  assert(manana > en10dias);
});

Deno.test("computeRanking: bill critica vencida le gana a una deuda con interes pero no vencida", () => {
  const ranked = computeRanking(
    [bill("b1", "2026-10-08", "critica", true)],
    [],
    [debt("d1", { dueDate: "2026-10-25", rate: 3.5, balance: 5000 })],
    "avalanche",
    TODAY,
  );
  assertEquals(ranked[0].id, "b1");
  assertEquals(ranked[1].id, "d1");
});

Deno.test("computeRanking: avalancha ordena deudas vencidas por tasa, mayor primero", () => {
  const ranked = computeRanking(
    [],
    [],
    [
      debt("baja-tasa", { dueDate: "2026-10-03", isOverdue: true, rate: 6, balance: 500 }),
      debt("alta-tasa", { dueDate: "2026-10-01", isOverdue: true, rate: 18, balance: 2000 }),
    ],
    "avalanche",
    TODAY,
  );
  assertEquals(ranked[0].id, "alta-tasa");
  assertEquals(ranked[1].id, "baja-tasa");
});

Deno.test("computeRanking: bola de nieve ordena deudas vencidas por saldo, menor primero", () => {
  const ranked = computeRanking(
    [],
    [],
    [
      debt("saldo-alto", { dueDate: "2026-10-01", isOverdue: true, rate: 18, balance: 2000 }),
      debt("saldo-bajo", { dueDate: "2026-10-03", isOverdue: true, rate: 6, balance: 500 }),
    ],
    "snowball",
    TODAY,
  );
  assertEquals(ranked[0].id, "saldo-bajo");
  assertEquals(ranked[1].id, "saldo-alto");
});

Deno.test("computeRanking: prioridad critica vence en 2 dias le gana a prioridad normal que vence en 10", () => {
  const ranked = computeRanking(
    [
      bill("normal-10d", "2026-10-22", "normal", false),
      bill("critica-2d", "2026-10-14", "critica", false),
    ],
    [],
    [],
    "avalanche",
    TODAY,
  );
  assertEquals(ranked[0].id, "critica-2d");
  assertEquals(ranked[1].id, "normal-10d");
});

Deno.test("computeRanking: deuda sin tasa conocida (avalancha) se marca con datos faltantes y no le gana a una con tasa alta", () => {
  const ranked = computeRanking(
    [],
    [],
    [
      debt("sin-tasa", { dueDate: "2026-10-01", isOverdue: true, rate: null, balance: 1000 }),
      debt("con-tasa", { dueDate: "2026-10-01", isOverdue: true, rate: 20, balance: 1000 }),
    ],
    "avalanche",
    TODAY,
  );
  assertEquals(ranked[0].id, "con-tasa");
  assertEquals(ranked[1].id, "sin-tasa");
  assert(ranked.find((r) => r.id === "sin-tasa")!.hasMissingData, "debe marcarse hasMissingData cuando falta la tasa");
  assert(!ranked.find((r) => r.id === "con-tasa")!.hasMissingData);
});

Deno.test("computeRanking: deuda sin due_date se marca con datos faltantes", () => {
  const ranked = computeRanking([], [], [debt("sin-fecha", { dueDate: null, rate: 5, balance: 500 })], "avalanche", TODAY);
  assert(ranked[0].hasMissingData);
});

Deno.test("computeRanking: bill sin datos faltantes no se marca", () => {
  const ranked = computeRanking([bill("b1", "2026-10-20", "normal", false)], [], [], "avalanche", TODAY);
  assert(!ranked[0].hasMissingData);
});

Deno.test("computeRanking: es determinista — mismos datos, mismo orden en llamadas repetidas", () => {
  const bills = [bill("b1", "2026-10-14", "critica", false), bill("b2", "2026-10-22", "normal", false)];
  const debts = [debt("d1", { dueDate: "2026-10-01", isOverdue: true, rate: 18, balance: 2000 })];
  const first = computeRanking(bills, [], debts, "avalanche", TODAY).map((r) => r.id);
  const second = computeRanking(bills, [], debts, "avalanche", TODAY).map((r) => r.id);
  assertEquals(first, second);
});

Deno.test("computeRanking: lista vacia no truena, regresa array vacio", () => {
  assertEquals(computeRanking([], [], [], "avalanche", TODAY), []);
});

Deno.test("isBillOverdue: due_date pasado es vencido, futuro no", () => {
  assert(isBillOverdue({ due_date: "2026-10-01" }, TODAY));
  assert(!isBillOverdue({ due_date: "2026-10-20" }, TODAY));
  assert(!isBillOverdue({ due_date: null }, TODAY));
});

Deno.test("fallbackReason: deuda vencida menciona mora", () => {
  const ranked = computeRanking([], [], [debt("d1", { dueDate: "2026-10-01", isOverdue: true, rate: 5, balance: 100 })], "avalanche", TODAY);
  assert(fallbackReason(ranked[0], "avalanche").toLowerCase().includes("mora"));
});

Deno.test("fallbackReason: item con datos faltantes dice que es estimado, no definitivo", () => {
  const ranked = computeRanking([], [], [debt("d1", { dueDate: null, rate: 5, balance: 100 })], "avalanche", TODAY);
  const reason = fallbackReason(ranked[0], "avalanche");
  assert(reason.includes("estimado") || reason.includes("no es definitivo"));
});

Deno.test("liquidityNote: ingreso alcanza para todo", () => {
  const note = liquidityNote([{ amount: 100 }, { amount: 200 }], 500);
  assert(note.includes("alcanza"));
  assert(!note.includes("NO alcanza"));
});

Deno.test("liquidityNote: ingreso NO alcanza, dice hasta donde si cubre", () => {
  const note = liquidityNote([{ amount: 300 }, { amount: 250 }, { amount: 100 }], 400);
  assert(note.includes("NO alcanza"));
  assert(note.includes("primeros 1")); // 400 cubre el primero (300), el segundo (300+250=550) ya no
});

Deno.test("liquidityNote: ingreso exacto al centavo cuenta como que si alcanza", () => {
  const note = liquidityNote([{ amount: 100 }], 100);
  assert(note.includes("alcanza"));
  assert(!note.includes("NO alcanza"));
});

Deno.test("liquidityNote: plan vacio no truena (total 0, siempre alcanza)", () => {
  const note = liquidityNote([], 100);
  assert(note.includes("alcanza"));
});
