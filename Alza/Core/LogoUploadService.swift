import Foundation

/// Sube el logo del negocio al bucket publico "business-logos" (una
/// carpeta por usuario, ver migracion 0010_invoicing.sql). El logo se
/// incrusta en facturas/recibos que se comparten FUERA de la app, por eso
/// el bucket es de lectura publica. Delega en StorageUploadService (el
/// patron generico de subida que usa toda la app).
enum LogoUploadService {
    private static let bucket = "business-logos"

    static func upload(userId: UUID, imageData: Data) async throws -> String {
        let path = "\(userId.uuidString)/logo.jpg"
        try await StorageUploadService.upload(bucket: bucket, path: path, data: imageData, contentType: "image/jpeg")
        return path
    }

    static func publicURL(forPath path: String) -> URL? {
        StorageUploadService.publicURL(bucket: bucket, path: path)
    }
}
