import SwiftUI

/// Document selection view - matches mockup screen 3
struct DocumentSelectionView: View {
    let allowedTypes: [DocumentType]
    let selectedCountry: CountryInfo?
    let onSelect: (DocumentType) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar (step 2/5)
            StepProgressBar(total: 5, current: 2)

            // Header with back button
            HStack(spacing: 12) {
                LightBackButton(action: onCancel)
                Text("Choose your document")
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundColor(KoraColors.TextPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            // Country indicator
            if let country = selectedCountry {
                Text("\(country.flagEmoji) \(country.name)")
                    .font(.system(size: 14))
                    .foregroundColor(KoraColors.TextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }

            // Document list
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(allowedTypes, id: \.self) { docType in
                        DocumentCard(docType: docType) {
                            onSelect(docType)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
        }
        .background(Color.white)
    }
}

// MARK: - Document Card

private struct DocumentCard: View {
    let docType: DocumentType
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundColor(iconTint)
                    .frame(width: 48, height: 48)
                    .background(iconBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(docType.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(KoraColors.TextPrimary)
                    Text(docType.requiresBack ? "Front & back required" : "Photo page only")
                        .font(.system(size: 13))
                        .foregroundColor(KoraColors.TextSecondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#CCCCCC"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .background(KoraColors.Surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var iconName: String {
        let name = docType.rawValue
        if name.contains("passport") { return "book.closed.fill" }
        if name.contains("driver") { return "creditcard.fill" }
        if name.contains("green_card") || name.contains("resident") { return "person.text.rectangle.fill" }
        return "creditcard.fill"
    }

    private var iconBg: Color {
        let name = docType.rawValue
        if name.contains("passport") { return KoraColors.WarningAmberLight }
        if name.contains("green_card") || name.contains("resident") { return KoraColors.IndigoLight }
        return KoraColors.InfoBlueLight
    }

    private var iconTint: Color {
        let name = docType.rawValue
        if name.contains("passport") { return KoraColors.WarningAmber }
        if name.contains("green_card") || name.contains("resident") { return KoraColors.Indigo }
        return KoraColors.InfoBlue
    }
}
