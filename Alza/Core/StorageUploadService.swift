import Foundation
import Supabase

/// Subida generica a Supabase Storage (S3-compatible) para CUALQUIER
/// imagen que la app necesite guardar — hoy el logo del negocio, mañana
/// lo que sea. La regla es siempre la misma: el archivo va al bucket, y
/// en la base solo se guarda el PATH (texto corto), nunca los bytes de
/// la imagen ni una URL firmada que expira. La URL publica se construye
/// al vuelo con `publicURL(bucket:path:)` cuando se necesita mostrarla.
///
/// Por que importa para "no afectar la data si escalo o cambio de
/// servidor": las filas de la base (`business_settings.logo_path`, etc.)
/// nunca dependen de en que host/CDN vive el archivo — son solo
/// "carpeta/usuario/archivo". Si el dia de mañana se migra a otro
/// proyecto de Supabase o a un bucket self-hosted, basta con copiar los
/// objetos del bucket; ninguna fila de la base de datos de usuarios tiene
/// que tocarse.
enum StorageUploadService {
    static func upload(bucket: String, path: String, data: Data, contentType: String) async throws {
        try await SupabaseManager.shared.client.storage.from(bucket).upload(
            path,
            data: data,
            options: FileOptions(contentType: contentType, upsert: true)
        )
    }

    static func publicURL(bucket: String, path: String) -> URL? {
        try? SupabaseManager.shared.client.storage.from(bucket).getPublicURL(path: path)
    }

    static func delete(bucket: String, path: String) async throws {
        try await SupabaseManager.shared.client.storage.from(bucket).remove(paths: [path])
    }
}
