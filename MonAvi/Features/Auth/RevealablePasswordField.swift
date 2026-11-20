import SwiftUI

/// Campo de contraseña con un ojito para verla u ocultarla. Al tocar el
/// ojito el cursor se queda en el campo.
struct RevealablePasswordField: View {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType = .password

    @State private var isRevealed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)

            Button {
                let wasFocused = focused
                isRevealed.toggle()
                if wasFocused {
                    DispatchQueue.main.async { focused = true }
                }
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Ocultar contraseña" : "Mostrar contraseña")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}
