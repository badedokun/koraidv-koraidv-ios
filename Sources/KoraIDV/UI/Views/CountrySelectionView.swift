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
                Text(L10n.tr("koraidv.country.title"))
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(KoraColors.TextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            // Subtitle
            Text(L10n.tr("koraidv.country.subtitle"))
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(selected.name), selected")
            }

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#AAAAAA"))
                TextField(L10n.tr("koraidv.country.search"), text: $searchQuery)
                    .font(.system(size: 15))
                    .accessibilityLabel("Search countries")
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
                        .accessibilityLabel(country.name)
                        .accessibilityValue(isSelected ? "Selected" : "")
                    }
                }
                .padding(.horizontal, 24)
            }

            // Continue button
            VStack {
                KoraButton(
                    text: L10n.tr("koraidv.country.continue"),
                    action: { if let c = selectedCountry { onSelect(c) } },
                    enabled: selectedCountry != nil
                )
                .accessibilityHint("Double tap to continue with selected country")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.white)
    }
}
