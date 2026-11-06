import SwiftUI
import Supabase

/// Lee y guarda edad y genero de `profiles` (los mismos campos del
/// onboarding) para poder corregirlos despues desde Ajustes.
@MainActor
final class ProfileSettingsViewModel: ObservableObject {
    @Published var ageText = ""
    @Published var gender: ProfileGender?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var didSave = false

    private let supabase = SupabaseManager.shared.client

    private struct ProfileRow: Decodable {
        let age: Int?
        let gender: String?
    }

    /// Manda `null` explicito cuando el campo queda vacio, para poder
    /// borrar un dato (el Encodable sintetizado omitiria la clave).
    private struct ProfileUpdate: Encodable {
        let age: Int?
        let gender: String?

        enum CodingKeys: String, CodingKey {
            case age
            case gender
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let age {
                try container.encode(age, forKey: .age)
            } else {
                try container.encodeNil(forKey: .age)
            }
            if let gender {
                try container.encode(gender, forKey: .gender)
            } else {
                try container.encodeNil(forKey: .gender)
            }
        }
    }

    /// Edad valida (1 a 120) o nil si el campo esta vacio. Devuelve
    /// `.failure` si escribio algo que no es una edad razonable.
    static func parseAge(_ text: String) -> Result<Int?, ProfileAgeError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .success(nil) }
        guard let age = Int(trimmed), (1...120).contains(age) else {
            return .failure(.invalid)
        }
        return .success(age)
    }

    func load(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let row: ProfileRow = try await supabase
                .from("profiles")
                .select("age, gender")
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            ageText = row.age.map { String($0) } ?? ""
            gender = row.gender.flatMap { ProfileGender(rawValue: $0) }
        } catch {
            errorMessage = "No se pudo cargar tu perfil: \(error.localizedDescription)"
        }
    }

    func save(userId: UUID) async {
        let age: Int?
        switch Self.parseAge(ageText) {
        case .success(let value):
            age = value
        case .failure:
            errorMessage = "Escribe una edad válida (de 1 a 120) o déjala vacía."
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await supabase
                .from("profiles")
                .update(ProfileUpdate(age: age, gender: gender?.rawValue))
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

/// "Mi perfil" en Ajustes: edad y genero (opcionales).
struct ProfileSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ProfileSettingsViewModel()

    var body: some View {
        Form {
            Section {
                TextField("Edad", text: $viewModel.ageText)
                    .keyboardType(.numberPad)

                Picker("Género", selection: $viewModel.gender) {
                    Text("Sin especificar").tag(ProfileGender?.none)
                    ForEach(ProfileGender.allCases) { gender in
                        Text(gender.displayName).tag(Optional(gender))
                    }
                }
            } footer: {
                Text("Opcional. Nos ayuda a darte consejos acordes a tu etapa de vida y a entender, de forma anónima y agregada, qué compran las personas como tú.")
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text(viewModel.didSave ? "Guardado" : "Guardar")
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isSaving || viewModel.isLoading)
            }
        }
        .navigationTitle("Mi perfil")
        .task { await load() }
        .onChange(of: viewModel.ageText) { _, _ in viewModel.didSave = false }
        .onChange(of: viewModel.gender) { _, _ in viewModel.didSave = false }
        .alert("Algo salió mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func load() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.load(userId: userId)
    }

    private func save() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.save(userId: userId)
    }
}
