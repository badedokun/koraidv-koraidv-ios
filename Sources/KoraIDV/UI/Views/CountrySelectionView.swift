import SwiftUI

/// Country info for selection
struct CountryInfo: Identifiable, Equatable {
    let id: String  // ISO 3166-1 alpha-2
    let name: String
    let flagEmoji: String
    let documentTypes: [DocumentType]
}

/// Country selection view
struct CountrySelectionView: View {
    let countries: [CountryInfo]
    let onSelect: (CountryInfo) -> Void
    let onCancel: () -> Void

    @State private var searchQuery = ""
    @State private var selectedCountry: CountryInfo?

    private var filteredCountries: [CountryInfo] {
        if searchQuery.isEmpty {
            return countries
        }
        return countries.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.id.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StepProgressBar(total: 5, current: 2)

            // Header
            HStack(spacing: 12) {
                LightBackButton(action: onCancel)
                Text("Select your country")
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(KoraColors.TextPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            // Subtitle
            Text("Where was your document issued?")
                .font(.system(size: 14))
                .foregroundColor(KoraColors.TextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

            // Selected country indicator
            if let selected = selectedCountry {
                HStack {
                    Text(selected.flagEmoji)
                        .font(.system(size: 28))
                    Spacer().frame(width: 12)
                    Text(selected.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(KoraColors.TextPrimary)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(KoraColors.Teal)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(KoraColors.SelectedBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(KoraColors.Teal, lineWidth: 2)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#AAAAAA"))
                TextField("Search countries...", text: $searchQuery)
                    .font(.system(size: 15))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(KoraColors.SurfaceLight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(KoraColors.BorderLight, lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Country list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredCountries) { country in
                        let isSelected = selectedCountry == country
                        Button(action: { selectedCountry = country }) {
                            HStack(spacing: 14) {
                                Text(country.flagEmoji)
                                    .font(.system(size: 24))
                                Text(country.name)
                                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                                    .foregroundColor(isSelected ? KoraColors.Teal : KoraColors.TextDark)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(KoraColors.Teal)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(isSelected ? KoraColors.SelectedBg : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                isSelected ?
                                    AnyView(
                                        HStack {
                                            Rectangle().fill(KoraColors.Teal).frame(width: 3)
                                            Spacer()
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    ) : AnyView(EmptyView())
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
            }

            // Continue button
            VStack {
                KoraButton(
                    text: "Continue",
                    action: { if let c = selectedCountry { onSelect(c) } },
                    enabled: selectedCountry != nil
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.white)
    }
}

/// Default countries list
extension CountrySelectionView {
    static var defaultCountries: [CountryInfo] {
        [
            CountryInfo(id: "US", name: "United States", flagEmoji: "\u{1F1FA}\u{1F1F8}", documentTypes: [.usDriversLicense, .usStateId, .usGreenCard, .internationalPassport]),
            CountryInfo(id: "GB", name: "United Kingdom", flagEmoji: "\u{1F1EC}\u{1F1E7}", documentTypes: [.internationalPassport]),
            CountryInfo(id: "DE", name: "Germany", flagEmoji: "\u{1F1E9}\u{1F1EA}", documentTypes: [.euIdGermany, .internationalPassport]),
            CountryInfo(id: "FR", name: "France", flagEmoji: "\u{1F1EB}\u{1F1F7}", documentTypes: [.euIdFrance, .internationalPassport]),
            CountryInfo(id: "ES", name: "Spain", flagEmoji: "\u{1F1EA}\u{1F1F8}", documentTypes: [.euIdSpain, .internationalPassport]),
            CountryInfo(id: "IT", name: "Italy", flagEmoji: "\u{1F1EE}\u{1F1F9}", documentTypes: [.euIdItaly, .internationalPassport]),
            CountryInfo(id: "GH", name: "Ghana", flagEmoji: "\u{1F1EC}\u{1F1ED}", documentTypes: [.ghanaCard, .internationalPassport]),
            CountryInfo(id: "NG", name: "Nigeria", flagEmoji: "\u{1F1F3}\u{1F1EC}", documentTypes: [.nigeriaNin, .internationalPassport]),
            CountryInfo(id: "KE", name: "Kenya", flagEmoji: "\u{1F1F0}\u{1F1EA}", documentTypes: [.kenyaId, .internationalPassport]),
            CountryInfo(id: "ZA", name: "South Africa", flagEmoji: "\u{1F1FF}\u{1F1E6}", documentTypes: [.southAfricaId, .internationalPassport]),
        ]
    }
}
