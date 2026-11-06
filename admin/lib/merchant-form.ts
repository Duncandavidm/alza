import "server-only";
import { optionalText, parseMapsUrl, text } from "./validation";

export type MerchantFields = {
  name: string;
  ruc: string;
  category: string | null;
  address: string | null;
  maps_url: string | null;
};

/// Lee y valida la "ficha" del comercio desde un formulario del panel.
export function parseMerchantFields(formData: FormData): { fields?: MerchantFields; error?: string } {
  const name = text(formData, "name", 120);
  const ruc = text(formData, "ruc", 40);
  if (!name) return { error: "El nombre es obligatorio." };
  if (!ruc) return { error: "El RUC es obligatorio." };

  const maps = parseMapsUrl(text(formData, "maps_url", 600));
  if (maps.error) return { error: maps.error };

  return {
    fields: {
      name,
      ruc,
      category: optionalText(formData, "category", 80),
      address: optionalText(formData, "address", 300),
      maps_url: maps.url,
    },
  };
}

export function friendlyDbError(error: { code?: string; message: string }): string {
  if (error.code === "23505") return "Ya existe un comercio aliado con ese RUC.";
  if (error.code === "23503") return "No se puede borrar: tiene canjes registrados. Pausa el producto en su lugar.";
  return error.message;
}
