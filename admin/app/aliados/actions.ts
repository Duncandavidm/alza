"use server";

import { supabaseAdmin } from "@/lib/supabase-admin";
import { MERCHANT_CATEGORIES } from "@/lib/merchant-categories";
import { isValidEmail, optionalText, parseHttpUrl, parseMapsUrl, text } from "@/lib/validation";

export type ApplicationFormState = { ok?: boolean; error?: string };

// Accion PUBLICA (sin sesion): la landing /aliados es publica en
// proxy.ts. Por eso: honeypot, tiempo minimo de llenado, limites de
// largo, validacion estricta, y nunca devuelve datos de la base.
export async function submitMerchantApplication(
  _prev: ApplicationFormState,
  formData: FormData
): Promise<ApplicationFormState> {
  // Honeypot: un campo oculto que una persona nunca llena.
  if (text(formData, "website", 200)) return { ok: true };

  // Un bot que envia el formulario en menos de 3 s tampoco es una persona.
  const startedAt = Number(text(formData, "started_at", 20));
  if (Number.isFinite(startedAt) && startedAt > 0 && Date.now() - startedAt < 3000) return { ok: true };

  const businessName = text(formData, "business_name", 200);
  const contactName = text(formData, "contact_name", 200);
  const email = text(formData, "email", 200).toLowerCase();

  if (businessName.length < 2 || businessName.length > 120) {
    return { error: "Escribe el nombre de tu negocio (máximo 120 caracteres)." };
  }
  if (contactName.length < 2 || contactName.length > 120) {
    return { error: "Escribe tu nombre (máximo 120 caracteres)." };
  }
  if (!isValidEmail(email)) return { error: "Revisa tu correo electrónico." };

  const phone = optionalText(formData, "phone", 40);
  if (phone && !/^[+\d\s().-]{7,30}$/.test(phone)) return { error: "Revisa tu número de teléfono." };

  const ruc = optionalText(formData, "ruc", 60);
  if (ruc && (ruc.length > 40 || !/^[\w\s.-]+$/.test(ruc))) return { error: "Revisa el RUC." };

  const categoryRaw = optionalText(formData, "category", 80);
  const category = categoryRaw && (MERCHANT_CATEGORIES as readonly string[]).includes(categoryRaw) ? categoryRaw : null;

  const address = optionalText(formData, "address", 400);
  if (address && address.length > 300) return { error: "La dirección es muy larga (máximo 300 caracteres)." };

  const mapsRaw = text(formData, "maps_url", 600);
  const maps = parseMapsUrl(mapsRaw);
  if (maps.error) return { error: maps.error };

  let instagram = optionalText(formData, "instagram", 200);
  if (instagram) {
    const asUrl = parseHttpUrl(instagram);
    if (asUrl) {
      const host = new URL(asUrl).hostname.replace(/^www\./, "");
      if (host !== "instagram.com") return { error: "Escribe tu usuario de Instagram (por ejemplo @minegocio)." };
      instagram = `@${new URL(asUrl).pathname.split("/").filter(Boolean)[0] ?? ""}`;
    } else {
      instagram = `@${instagram.replace(/^@+/, "")}`;
    }
    if (!/^@[A-Za-z0-9._]{1,30}$/.test(instagram)) {
      return { error: "Escribe tu usuario de Instagram (por ejemplo @minegocio)." };
    }
  }

  const message = optionalText(formData, "message", 1200);
  if (message && message.length > 1000) return { error: "El mensaje es muy largo (máximo 1000 caracteres)." };

  try {
    const supabase = supabaseAdmin();

    // Doble envio (o reintento): misma solicitud en las ultimas 24 h.
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count } = await supabase
      .from("merchant_applications")
      .select("id", { count: "exact", head: true })
      .eq("email", email)
      .eq("business_name", businessName)
      .gte("created_at", since);
    if ((count ?? 0) > 0) return { ok: true };

    const { error } = await supabase.from("merchant_applications").insert({
      business_name: businessName,
      ruc,
      contact_name: contactName,
      email,
      phone,
      category,
      address,
      maps_url: maps.url,
      instagram,
      message,
    });
    if (error) {
      console.error("merchant_applications insert failed", error.message);
      return { error: "No pudimos enviar tu solicitud. Inténtalo de nuevo en unos minutos." };
    }
  } catch (error) {
    console.error("merchant_applications insert failed", error);
    return { error: "No pudimos enviar tu solicitud. Inténtalo de nuevo en unos minutos." };
  }

  return { ok: true };
}
