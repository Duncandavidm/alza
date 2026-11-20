import "server-only";
import { supabaseAdmin } from "./supabase-admin";

// Bucket publico de lectura (migracion 0031): logos de comercios y
// fotos de productos canjeables. Solo el panel sube (service role).
const BUCKET = "rewards";
const MAX_BYTES = 5 * 1024 * 1024;
const EXTENSIONS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

/// Toma el archivo de un <input type="file">. Devuelve null si no se
/// eligio ninguno (el navegador manda un File vacio en ese caso).
export function fileFromForm(formData: FormData, key: string): File | null {
  const value = formData.get(key);
  if (!value || typeof value === "string") return null;
  if (value.size === 0) return null;
  return value;
}

export function validateImage(file: File): string | null {
  if (!EXTENSIONS[file.type]) return "La imagen debe ser JPG, PNG o WebP.";
  if (file.size > MAX_BYTES) return "La imagen pesa más de 5 MB.";
  return null;
}

/// Sube la imagen a `rewards/<folder>/<baseName>-<timestamp>.<ext>` y
/// devuelve su URL publica.
export async function uploadRewardImage(
  file: File,
  folder: "logos" | "products",
  baseName: string
): Promise<{ url?: string; error?: string }> {
  const invalid = validateImage(file);
  if (invalid) return { error: invalid };

  const path = `${folder}/${baseName}-${Date.now()}.${EXTENSIONS[file.type]}`;
  const supabase = supabaseAdmin();
  const bytes = new Uint8Array(await file.arrayBuffer());
  const { error } = await supabase.storage.from(BUCKET).upload(path, bytes, {
    contentType: file.type,
    upsert: false,
  });
  if (error) return { error: `No se pudo subir la imagen: ${error.message}` };

  const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
  return { url: data.publicUrl };
}
