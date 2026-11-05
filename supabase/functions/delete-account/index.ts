// Edge Function: delete-account
//
// Apple exige (Guideline 5.1.1(v)) que cualquier app que permite crear una
// cuenta tambien permita eliminarla desde dentro de la app. Esta funcion
// es ese boton: borra la cuenta de auth.users del usuario que llama,
// nunca la de otro (userId SIEMPRE del JWT verificado, nunca del body —
// mismo patron de seguridad que el resto de las funciones, ver
// supabase/functions/README_SECURITY.md).
//
// No hace falta borrar nada mas a mano: CADA tabla con datos del usuario
// (transactions, accounts, budgets, debts, savings_goals, bills,
// recurring_transactions, ai_insights, subscriptions, invoices, products,
// business_settings, feedback_suggestions, points_ledger, linked_cards,
// dgi_receipts, sponsored_savings_enrollments, family_groups/members,
// etc.) tiene `user_id ... references auth.users (id) on delete cascade`
// — borrar la fila de auth.users se encarga de todo (verificado barriendo
// las migraciones: la unica excepcion es card_transactions.user_id, que es
// `on delete set null` a proposito porque esa tabla es la mesa de trabajo
// de la reconciliacion de puntos de tarjeta, no datos del usuario).
//
// Si el usuario es dueno de un grupo familiar con miembros, el grupo se
// borra en cascada y esos miembros pierden su acceso Pro heredado al
// instante — la app avisa de esto ANTES de llamar a esta funcion (ver
// DeleteAccountView.swift), aqui no se valida ni se bloquea por eso.
//
// Sin rate limiting a proposito: es una accion propia, autodestructiva,
// que no cuesta nada llamar de mas (al segundo intento el usuario ya no
// existe y el admin API regresa un error, no hay forma de abusarla).

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function getVerifiedUserId(req: Request): string | null {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;
  const parts = authHeader.slice(7).split(".");
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    const userId = getVerifiedUserId(req);
    if (!userId) {
      return jsonResponse({ error: "No autorizado" }, 401);
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { error } = await supabase.auth.admin.deleteUser(userId);
    if (error) throw error;

    return jsonResponse({ deleted: true });
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: String(error) }, 500);
  }
});
