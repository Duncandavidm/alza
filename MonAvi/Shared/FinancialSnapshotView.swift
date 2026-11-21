import SwiftUI

/// Muestra "Tu foto financiera": diagnóstico, números clave y el plan de
/// hasta 3 pasos. Va dentro de un Form/List (son Sections).
struct FinancialSnapshotSections: View {
    let snapshot: FinancialSnapshot
    var name: String = ""
    /// Al final del onboarding: decir donde volver a verlo.
    var showRevisitHint = true

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(snapshot.health.emoji)
                    .font(.system(size: 44))
                Text(name.isEmpty ? snapshot.health.title : "\(name), \(snapshot.health.title.lowercased())")
                    .font(.title2.bold())
                Text("Así se ve tu vida financiera con lo que nos contaste. No es un juicio: es el punto de partida.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }

        if snapshot.monthlyIncome > 0 {
            Section {
                MoneySplitBar(snapshot: snapshot)
                    .padding(.vertical, 6)
            } header: {
                Text("A dónde va tu ingreso fijo")
            }
        }

        if let utilization = snapshot.creditUtilization {
            Section("Uso de tus tarjetas") {
                CreditUseRow(utilization: utilization, balance: snapshot.debts.filter { ($0.creditLimit ?? 0) > 0 }.reduce(0) { $0 + $1.balance },
                             limit: snapshot.debts.reduce(0) { $0 + ($1.creditLimit ?? 0) })
            }
        }

        Section("Lo que vemos") {
            ForEach(snapshot.observations) { line in
                SnapshotLineRow(line: line)
            }
        }

        Section {
            ForEach(snapshot.plan) { line in
                SnapshotLineRow(line: line, bold: true)
            }
        } header: {
            Text("Cómo vamos a mejorar")
        } footer: {
            Text(showRevisitHint
                 ? "MonAvi te va a recordar tus pagos fijos y te avisará cómo vas. Puedes volver a ver este análisis en Análisis > Tu salud financiera."
                 : "Se calcula con tus pagos fijos, deudas y cuentas en MonAvi. Si algo cambió, actualízalo y vuelve aquí.")
        }
    }
}

private struct SnapshotLineRow: View {
    let line: FinancialSnapshot.Line
    var bold = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line.emoji)
            Text(line.text)
                .font(bold ? .subheadline.weight(.semibold) : .subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

/// Barra de 100% partida en gastos fijos, deudas y lo que queda libre.
private struct MoneySplitBar: View {
    let snapshot: FinancialSnapshot
    @State private var appeared = false

    private struct Part: Identifiable {
        let id: String
        let value: Decimal
        let color: Color
    }

    private var parts: [Part] {
        let free = max(snapshot.freeMoney, 0)
        return [
            Part(id: "Gastos fijos", value: snapshot.fixedExpenses, color: Color(red: 0.24, green: 0.47, blue: 0.85)),
            Part(id: "Deudas", value: snapshot.debtPayments, color: Color(red: 0.93, green: 0.55, blue: 0.18)),
            Part(id: "Libre", value: free, color: MonAviBrand.primary),
        ].filter { $0.value > 0 }
    }

    var body: some View {
        let total = max(parts.reduce(Decimal(0)) { $0 + $1.value }, 1)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(parts) { part in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(part.color)
                            .frame(width: max(proxy.size.width * CGFloat((part.value / total).doubleValue) - 2, 4))
                    }
                }
                .frame(width: appeared ? proxy.size.width : 0, alignment: .leading)
                .clipped()
            }
            .frame(height: 14)

            ForEach(parts) { part in
                HStack {
                    Circle().fill(part.color).frame(width: 9, height: 9)
                    Text(part.id)
                    Spacer()
                    Text(FinancialSnapshot.money(part.value))
                        .fontWeight(.semibold)
                    Text(FinancialSnapshot.percent((part.value / max(snapshot.monthlyIncome, 1)).doubleValue))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.subheadline)
            }
            if snapshot.freeMoney < 0 {
                Text("Te faltan \(FinancialSnapshot.money(-snapshot.freeMoney)) al mes para cubrir lo fijo.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) { appeared = true }
        }
    }
}

/// Cuánto del cupo de tarjeta se está usando (verde hasta 30%).
struct CreditUseRow: View {
    let utilization: Double
    let balance: Decimal
    let limit: Decimal

    private var color: Color {
        utilization > 0.7 ? .red : utilization > 0.3 ? .orange : MonAviBrand.primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Usas el \(FinancialSnapshot.percent(utilization)) de tu cupo")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(FinancialSnapshot.money(balance)) de \(FinancialSnapshot.money(limit))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(utilization, 1))
                .tint(color)
            Text(utilization > 0.3 ? "Lo ideal es usar menos del 30%: cuida tu historial de crédito." : "Bien: estás por debajo del 30% recomendado.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
