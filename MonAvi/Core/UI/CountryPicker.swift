import SwiftUI

/// Lista de países con bandera y moneda (bienvenida y Mi perfil).
struct CountryPicker: View {
    @Binding var selection: AppCountry

    var body: some View {
        ForEach(AppCountry.allCases) { country in
            Button {
                selection = country
            } label: {
                HStack(spacing: 12) {
                    Text(country.flag)
                        .font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(country.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(country.currencyName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selection == country {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(MonAviBrand.primary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(country.name), \(country.currencyName)")
            .accessibilityAddTraits(selection == country ? .isSelected : [])
        }
    }
}
