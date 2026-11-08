import SwiftUI
import Supabase

/// "Mi perfil" en Ajustes: lee y guarda los datos personales de
/// `profiles` (los mismos campos del onboarding mas el telefono) para
/// poder corregirlos despues. Todo es opcional.
/// Misma regla que el check de `profiles.phone` en la base:
/// `^\+?[0-9 ()-]{7,20}$`.
private let profilePhonePattern = "^\\+?[0-9 ()-]{7,20}$"

@MainActor
final class ProfileSettingsViewModel: ObservableObject {
    @Published var fullName = ""
    @Published var phone = ""
    /// Edad elegida (18 a 99) o nil si no quiere decirla.
    @Published var age: Int?
    @Published var gender: ProfileGender?
    @Published var maritalStatus: MaritalStatus?
    /// nil = nunca lo indico; el Stepper lo vuelve 0...10 al tocarlo.
    @Published var dependentsCount: Int?
    @Published var occupation = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var didSave = false
    /// Correo verificado con codigo (RPC `email_is_verified`); nil
    /// mientras no se sabe (cargando o fallo la consulta).
    @Published private(set) var isEmailVerified: Bool?

    /// Rango de edades que ofrece el selector.
    static let ageRange = 18...99
    /// Rango del Stepper de dependientes.
    static let dependentsRange = 0...10

    private let supabase = SupabaseManager.shared.client

    private struct ProfileRow: Decodable {
        let fullName: String?
        let phone: String?
        let age: Int?
        let gender: String?
        let maritalStatus: String?
        let dependentsCount: Int?
        let occupation: String?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case phone
            case age
            case gender
            case maritalStatus = "marital_status"
            case dependentsCount = "dependents_count"
            case occupation
        }
    }

    /// Manda `null` explicito cuando un campo queda vacio, para poder
    /// borrar un dato (el Encodable sintetizado omitiria la clave).
    private struct ProfileUpdate: Encodable {
        let fullName: String?
        let phone: String?
        let age: Int?
        let gender: String?
        let maritalStatus: String?
        let dependentsCount: Int?
        let occupation: String?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case phone
            case age
            case gender
            case maritalStatus = "marital_status"
            case dependentsCount = "dependents_count"
            case occupation
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try Self.encodeOrNull(fullName, forKey: .fullName, in: &container)
            try Self.encodeOrNull(phone, forKey: .phone, in: &container)
            try Self.encodeOrNull(age, forKey: .age, in: &container)
            try Self.encodeOrNull(gender, forKey: .gender, in: &container)
            try Self.encodeOrNull(maritalStatus, forKey: .maritalStatus, in: &container)
            try Self.encodeOrNull(dependentsCount, forKey: .dependentsCount, in: &container)
            try Self.encodeOrNull(occupation, forKey: .occupation, in: &container)
        }

        private static func encodeOrNull<T: Encodable>(
            _ value: T?,
            forKey key: CodingKeys,
            in container: inout KeyedEncodingContainer<CodingKeys>
        ) throws {
            if let value {
                try container.encode(value, forKey: key)
            } else {
                try container.encodeNil(forKey: key)
            }
        }
    }

    /// Edad valida (1 a 120) o nil si el campo esta vacio. Devuelve
    /// `.failure` si escribio algo que no es una edad razonable.
    nonisolated static func parseAge(_ text: String) -> Result<Int?, ProfileAgeError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .success(nil) }
        guard let age = Int(trimmed), (1...120).contains(age) else {
            return .failure(.invalid)
        }
        return .success(age)
    }

    /// Telefono limpio (sin espacios a los lados) o nil si quedo vacio.
    /// `.failure` si no cumple el formato que acepta la base.
    nonisolated static func parsePhone(_ text: String) -> Result<String?, ProfilePhoneError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .success(nil) }
        guard trimmed.range(of: profilePhonePattern, options: .regularExpression) != nil else {
            return .failure(.invalid)
        }
        return .success(trimmed)
    }

    /// Texto vacio -> nil (para mandar `null` y no "").
    nonisolated static func cleanedText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Error en linea bajo el telefono, o nil si esta bien (o vacio).
    var phoneError: String? {
        switch Self.parsePhone(phone) {
        case .success:
            return nil
        case .failure:
            return "Escribe un teléfono válido: de 7 a 20 dígitos; puede llevar +, espacios, guiones o paréntesis."
        }
    }

    /// Opciones del selector de edad: 18 a 99 y, si el perfil ya traia
    /// una edad fuera de ese rango, tambien esa (para no perderla).
    var ageOptions: [Int] {
        var options = Array(Self.ageRange)
        if let age, !Self.ageRange.contains(age) {
            options.append(age)
            options.sort()
        }
        return options
    }

    func load(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let row: ProfileRow = try await supabase
                .from("profiles")
                .select("full_name, phone, age, gender, marital_status, dependents_count, occupation")
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            fullName = row.fullName ?? ""
            phone = row.phone ?? ""
            age = row.age
            gender = row.gender.flatMap { ProfileGender(rawValue: $0) }
            maritalStatus = row.maritalStatus.flatMap { MaritalStatus(rawValue: $0) }
            dependentsCount = row.dependentsCount
            occupation = row.occupation ?? ""
            didSave = false
        } catch {
            errorMessage = "No se pudo cargar tu perfil: \(error.localizedDescription)"
        }
    }

    /// Pregunta al servidor si el correo ya se verifico (los que entraron
    /// con Apple ya cuentan como verificados). Si falla, no muestra nada.
    func loadEmailVerification(userId: UUID) async {
        isEmailVerified = try? await EmailVerificationService.shared.isVerified(userId: userId)
    }

    func markEmailVerified() {
        isEmailVerified = true
    }

    func save(userId: UUID) async {
        let cleanPhone: String?
        switch Self.parsePhone(phone) {
        case .success(let value):
            cleanPhone = value
        case .failure:
            errorMessage = "Revisa tu teléfono: de 7 a 20 dígitos; puede llevar +, espacios, guiones o paréntesis."
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await supabase
                .from("profiles")
                .update(
                    ProfileUpdate(
                        fullName: Self.cleanedText(fullName),
                        phone: cleanPhone,
                        age: age,
                        gender: gender?.rawValue,
                        maritalStatus: maritalStatus?.rawValue,
                        dependentsCount: dependentsCount,
                        occupation: Self.cleanedText(occupation)
                    )
                )
                .eq("id", value: userId)
                .execute()
            didSave = true
        } catch {
            errorMessage = "No se pudo guardar tu perfil: \(error.localizedDescription)"
        }
    }
}

enum ProfileAgeError: Error {
    case invalid
}

enum ProfilePhoneError: Error {
    case invalid
}

/// "Mi perfil" en Ajustes: cuenta, datos personales (opcionales) y sesion.
struct ProfileSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ProfileSettingsViewModel()
    @State private var isSigningOut = false
    @State private var isShowingEmailVerification = false

    var body: some View {
        Form {
            accountSection
            personalDataSection
            saveSection
            sessionSection
        }
        .navigationTitle("Mi perfil")
        .task { await load() }
        .onChange(of: viewModel.fullName) { _, _ in viewModel.didSave = false }
        .onChange(of: viewModel.phone) { _, _ in viewModel.didSave = false }
        .onChange(of: viewModel.age) { _, _ in viewModel.didSave = false }
        .onChange(of: viewModel.gender) { _, _ in viewModel.didSave = false }
        .onChange(of: viewModel.maritalStatus) { _, _ in viewModel.didSave = false }
        .onChange(of: viewModel.dependentsCount) { _, _ in viewModel.didSave = false }
        .onChange(of: viewModel.occupation) { _, _ in viewModel.didSave = false }
        .sheet(isPresented: $isShowingEmailVerification) {
            EmailVerificationSheet {
                viewModel.markEmailVerified()
            }
        }
        .alert("Algo salió mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Cuenta

    private var accountSection: some View {
        Section("Cuenta") {
            LabeledContent("Correo") {
                Text(email ?? "Sin correo")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let signInMethod {
                LabeledContent("Inicio de sesión", value: signInMethod)
            }
            if email != nil {
                emailVerificationRow
            }
        }
    }

    /// "Correo verificado ✓" o el boton para verificarlo (se pide antes
    /// del primer canje de premios).
    @ViewBuilder
    private var emailVerificationRow: some View {
        switch viewModel.isEmailVerified {
        case .some(true):
            Text("Correo verificado ✓")
                .foregroundStyle(MonAviBrand.primaryDark)
        case .some(false):
            Button {
                isShowingEmailVerification = true
            } label: {
                Label("Verificar correo", systemImage: "envelope.badge")
            }
        case .none:
            EmptyView()
        }
    }

    private var email: String? {
        guard let email = appState.session?.user.email?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !email.isEmpty else { return nil }
        return email
    }

    /// "Apple" o "Correo y contraseña", segun `app_metadata.provider`.
    private var signInMethod: String? {
        guard let metadata = appState.session?.user.appMetadata,
              case let .string(provider)? = metadata["provider"] else { return nil }
        switch provider.lowercased() {
        case "apple": return "Apple"
        case "email": return "Correo y contraseña"
        case "google": return "Google"
        default: return nil
        }
    }

    // MARK: - Datos personales

    private var personalDataSection: some View {
        Section {
            TextField("Nombre", text: $viewModel.fullName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Teléfono", text: $viewModel.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                if let phoneError = viewModel.phoneError {
                    Text(phoneError)
                        .font(.caption)
                        .foregroundStyle(MonAviBrand.alert)
                }
            }

            Picker("Edad", selection: $viewModel.age) {
                Text("Sin especificar").tag(Int?.none)
                ForEach(viewModel.ageOptions, id: \.self) { age in
                    Text("\(age) años").tag(Optional(age))
                }
            }

            Picker("Género", selection: $viewModel.gender) {
                Text("Sin especificar").tag(ProfileGender?.none)
                ForEach(ProfileGender.allCases) { gender in
                    Text(gender.displayName).tag(Optional(gender))
                }
            }

            Picker("Estado civil", selection: $viewModel.maritalStatus) {
                Text("Sin especificar").tag(MaritalStatus?.none)
                ForEach(MaritalStatus.allCases) { status in
                    Text(status.displayName).tag(Optional(status))
                }
            }

            Stepper(value: dependentsBinding, in: ProfileSettingsViewModel.dependentsRange) {
                LabeledContent("Dependientes") {
                    Text(viewModel.dependentsCount.map { String($0) } ?? "Sin especificar")
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Ocupación (ej. empleado, dueño de un negocio...)", text: $viewModel.occupation, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            Text("Datos personales")
        } footer: {
            Text("Opcional. Nos ayuda a darte consejos acordes a tu etapa de vida y a entender, de forma anónima y agregada, qué compran las personas como tú.")
        }
    }

    /// El Stepper trabaja con Int; nil se muestra como "Sin especificar"
    /// y arranca en 0 al tocarlo.
    private var dependentsBinding: Binding<Int> {
        Binding(
            get: { viewModel.dependentsCount ?? 0 },
            set: { viewModel.dependentsCount = $0 }
        )
    }

    private var saveSection: some View {
        Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSaving {
                        ProgressView()
                    } else if viewModel.didSave {
                        Label("Guardado", systemImage: "checkmark.circle.fill")
                    } else {
                        Text("Guardar")
                    }
                    Spacer()
                }
            }
            .disabled(viewModel.isSaving || viewModel.isLoading || viewModel.phoneError != nil)
        } footer: {
            if viewModel.didSave {
                Text("Tus datos se guardaron.")
                    .foregroundStyle(MonAviBrand.primaryDark)
            }
        }
    }

    // MARK: - Sesion

    private var sessionSection: some View {
        Section("Sesión") {
            Button(role: .destructive) {
                Task {
                    isSigningOut = true
                    await appState.signOut()
                    isSigningOut = false
                }
            } label: {
                if isSigningOut {
                    ProgressView()
                } else {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .disabled(isSigningOut)

            NavigationLink {
                DeleteAccountView()
            } label: {
                Label("Eliminar cuenta", systemImage: "trash.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func load() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.load(userId: userId)
        await viewModel.loadEmailVerification(userId: userId)
    }

    private func save() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.save(userId: userId)
    }
}
