import UserNotifications

/// Extension de notificaciones (1.0.3): si el aviso trae `image_url` (logo
/// del comercio o foto del cupon), la baja y la muestra a la derecha del
/// aviso, como los avisos de las apps de delivery. Si no hay imagen, tarda
/// o falla, el aviso llega igual, sin imagen.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        bestAttempt = content

        guard
            let raw = request.content.userInfo["image_url"] as? String,
            let url = URL(string: raw),
            url.scheme?.lowercased() == "https"
        else {
            contentHandler(content)
            return
        }

        let task = URLSession.shared.downloadTask(with: url) { location, response, _ in
            defer { contentHandler(content) }
            guard let location else { return }
            let fileExtension = Self.fileExtension(for: response?.mimeType, url: url)
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                let attachment = try UNNotificationAttachment(identifier: "imagen", url: destination)
                content.attachments = [attachment]
            } catch {
                // Sin imagen: el aviso sigue igual.
            }
        }
        task.resume()
    }

    /// iOS da unos segundos: si se acaba el tiempo, se entrega sin imagen.
    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttempt {
            contentHandler(bestAttempt)
        }
    }

    private static func fileExtension(for mimeType: String?, url: URL) -> String {
        switch mimeType?.lowercased() {
        case "image/png": return "png"
        case "image/webp": return "webp"
        case "image/gif": return "gif"
        case "image/jpeg", "image/jpg": return "jpg"
        default:
            let fromURL = url.pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "gif", "webp"].contains(fromURL) ? fromURL : "jpg"
        }
    }
}
