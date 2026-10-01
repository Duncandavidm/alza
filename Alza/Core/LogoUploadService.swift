import Foundation
import Supabase

/// Sube el logo del negocio al bucket publico "business-logos" (una
/// carpeta por usuario, ver migracion 0010_invoicing.sql). El logo se
/// incrusta en facturas/recibos que se comparten FUERA de la app, por eso
/// el bucket es de lectura publica.
enum LogoUploadService {
    private static let bucket = "business-logos"

    static func upload(userId: UUID, imageData: Data) async throws -> String {
        let supabase = SupabaseManager.shared.client
        let path = "\(userId.uuidString)/logo.jpg"

        try await supabase.storage.from(bucket).upload(
            path,
            data: imageData,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )

        return path
    }

    static func publicURL(forPath path: String) -> URL? {
        try? SupabaseManager.shared.client.storage.from(bucket).getPublicURL(path: path)
    }
}
