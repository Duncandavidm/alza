import Foundation
import SwiftUI
import Supabase

@MainActor
final class BusinessSettingsViewModel: ObservableObject {
    @Published var businessName = ""
    @Published var brandColor: Color = Color(hex: "#00A585") ?? .accentColor
    @Published var brandFont: BrandFont = .default
    @Published var taxId = ""
    @Published var address = ""
    @Published var phone = ""
    @Published private(set) var logoPath: String?

    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isUploadingLogo = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    var logoURL: URL? {
        guard let logoPath else { return nil }
        return LogoUploadService.publicURL(forPath: logoPath)
    }

    func load(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let settings: BusinessSettings? = try await supabase
                .from("business_settings")
                .select()
                .eq("user_id", value: userId)
                .maybeSingle()
                .execute()
                .value

            guard let settings else { return }
            businessName = settings.businessName ?? ""
            brandColor = settings.brandColor
            brandFont = settings.brandFont
            taxId = settings.taxId ?? ""
            address = settings.address ?? ""
            phone = settings.phone ?? ""
            logoPath = settings.logoPath
        } catch {
            errorMessage = "No se pudo cargar tu negocio: \(error.localizedDescription)"
        }
    }

    func uploadLogo(userId: UUID, imageData: Data) async {
        isUploadingLogo = true
        defer { isUploadingLogo = false }

        do {
            logoPath = try await LogoUploadService.upload(userId: userId, imageData: imageData)
            await save(userId: userId)
        } catch {
            errorMessage = "No se pudo subir el logo: \(error.localizedDescription)"
        }
    }

    func save(userId: UUID) async {
        isSaving = true
        defer { isSaving = false }

        do {
            let payload = BusinessSettingsUpsert(
                userId: userId,
                businessName: businessName.isEmpty ? nil : businessName,
                logoPath: logoPath,
                brandColor: brandColor.hexString,
                brandFont: brandFont,
                taxId: taxId.isEmpty ? nil : taxId,
                address: address.isEmpty ? nil : address,
                phone: phone.isEmpty ? nil : phone
            )

            try await supabase
                .from("business_settings")
                .upsert(payload, onConflict: "user_id")
                .execute()
        } catch {
            errorMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }
}
