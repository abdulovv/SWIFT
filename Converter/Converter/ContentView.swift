import SwiftUI
import Combine

// MARK: - Models
struct BankRate: Codable {
    let Cur_ID: Int
    let Cur_Abbreviation: String
    let Cur_OfficialRate: Double
    let Cur_Scale: Int
}

enum CurrencyType: String, CaseIterable {
    case usd = "USD", byn = "BYN", eur = "EUR", rub = "RUB", cny = "CNY"
    var symbol: String {
        switch self {
        case .usd: return "$"
        case .byn: return "Br"
        case .eur: return "€"
        case .rub: return "₽"
        case .cny: return "¥"
        }
    }
    var title: String {
        switch self {
        case .usd: return "Доллар США"
        case .byn: return "Белорусский рубль"
        case .eur: return "Евро"
        case .rub: return "Российский рубль"
        case .cny: return "Китайский юань"
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @AppStorage("usd_rate") private var usdRate = 3.25
    @AppStorage("eur_rate") private var eurRate = 3.55
    @AppStorage("rub_rate") private var rubRate = 3.50
    @AppStorage("cny_rate") private var cnyRate = 4.50
    
    @State private var amountString: String = ""
    @State private var selectedCurrency: CurrencyType = .usd
    @FocusState private var isInputFocused: Bool
    
    var currentAmountValue: Double {
        let normalized = amountString.replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? 1.0
    }
    
    var amountInBYN: Double {
        let value = currentAmountValue
        switch selectedCurrency {
        case .byn: return value
        case .usd: return value * usdRate
        case .eur: return value * eurRate
        case .rub: return value * (rubRate / 100)
        case .cny: return value * (cnyRate / 10)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                Form {
                    Section(header: Text("Введите сумму в \(selectedCurrency.rawValue)").foregroundColor(.blue)) {
                        HStack {
                            Text(selectedCurrency.symbol)
                                .font(.title2).bold().foregroundColor(.blue)
                            
                            TextField("1.00", text: $amountString)
                                .keyboardType(.decimalPad)
                                .focused($isInputFocused)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .onReceive(Just(amountString)) { newValue in
                                    let filtered = filterInvalidInput(newValue)
                                    if filtered != newValue { self.amountString = filtered }
                                }
                        }
                        .padding(.vertical, 10)
                    }
                    .listRowBackground(Color.blue.opacity(0.15))

                    Section {
                        ForEach(CurrencyType.allCases.filter { $0 != selectedCurrency }, id: \.self) { currency in
                            Button {
                                withAnimation {
                                    let currentBYN = amountInBYN
                                    selectedCurrency = currency
                                    let newVal = calculateValue(for: currency, from: currentBYN)
                                    amountString = formatCleanString(newVal)
                                }
                            } label: {
                                resultRow(
                                    title: currency.title,
                                    value: calculateValue(for: currency, from: amountInBYN),
                                    symbol: currency.rawValue
                                )
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await fetchBankRatesAsync() }
                .onChange(of: isInputFocused) { focused in
                    if !focused { cleanLeadingZeros() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Конвертер").font(.headline).foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: InfoView(usd: usdRate, eur: eurRate, rub: rubRate, cny: cnyRate)) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Helpers
    func cleanLeadingZeros() {
        let normalized = amountString.replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized) { amountString = formatCleanString(value) }
    }
    
    func formatCleanString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    func filterInvalidInput(_ input: String) -> String {
        var filtered = input.replacingOccurrences(of: ".", with: ",")
        let components = filtered.components(separatedBy: ",")
        if components.count > 2 { filtered = components[0] + "," + components[1] }
        return filtered
    }

    func calculateValue(for type: CurrencyType, from byn: Double) -> Double {
        switch type {
        case .byn: return byn
        case .usd: return byn / usdRate
        case .eur: return byn / eurRate
        case .rub: return byn / (rubRate / 100)
        case .cny: return byn / (cnyRate / 10)
        }
    }

    func resultRow(title: String, value: Double, symbol: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundColor(.gray)
                Text(symbol).font(.system(.subheadline, design: .monospaced)).foregroundColor(.blue.opacity(0.5))
            }
            Spacer()
            Text(String(format: "%.2f", value))
                .font(.title2).monospacedDigit().foregroundColor(.secondary)
        }
        .padding(.vertical, 5)
        .listRowBackground(Color.white.opacity(0.05))
    }

    func fetchBankRatesAsync() async {
        let urlString = "https://api.nbrb.by/exrates/rates?periodicity=0"
        guard let url = URL(string: urlString) else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url),
           let rates = try? JSONDecoder().decode([BankRate].self, from: data) {
            await MainActor.run {
                for rate in rates {
                    switch rate.Cur_Abbreviation {
                    case "USD": self.usdRate = rate.Cur_OfficialRate
                    case "EUR": self.eurRate = rate.Cur_OfficialRate
                    case "RUB": self.rubRate = rate.Cur_OfficialRate
                    case "CNY": self.cnyRate = rate.Cur_OfficialRate
                    default: break
                    }
                }
            }
        }
    }
}

// MARK: - Info View
struct InfoView: View {
    let usd: Double
    let eur: Double
    let rub: Double
    let cny: Double
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            List {
                Section(header: Text("Курсы Национального Банка").foregroundColor(.blue)) {
                    infoRow(title: "1 USD", value: usd)
                    infoRow(title: "1 EUR", value: eur)
                    infoRow(title: "100 RUB", value: rub)
                    infoRow(title: "10 CNY", value: cny)
                }
                .listRowBackground(Color.white.opacity(0.05))
                
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Информация")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func infoRow(title: String, value: Double) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
                .bold()
            Spacer()
            Text("\(String(format: "%.4f", value)) BYN")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
