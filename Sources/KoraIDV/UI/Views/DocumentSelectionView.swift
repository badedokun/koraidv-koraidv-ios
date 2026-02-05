import SwiftUI

/// Document selection view
struct DocumentSelectionView: View {
    let allowedTypes: [DocumentType]
    let onSelect: (DocumentType) -> Void
    let onCancel: () -> Void

    @Environment(\.koraTheme) private var theme
    @State private var selectedType: DocumentType?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Document list
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(groupedDocuments.keys.sorted(), id: \.self) { category in
                        documentSection(category: category, types: groupedDocuments[category] ?? [])
                    }
                }
                .padding(theme.padding)
            }

            // Footer
            footerView
        }
        .background(theme.backgroundColor)
    }

    private var headerView: some View {
        VStack(spacing: 4) {
            Text("Select Document Type")
                .font(theme.titleFont)
                .foregroundColor(theme.textColor)

            Text("Choose the type of ID you'll use for verification")
                .font(theme.bodyFont)
                .foregroundColor(theme.secondaryTextColor)
        }
        .padding(theme.padding)
    }

    private var footerView: some View {
        VStack(spacing: 12) {
            Button {
                if let type = selectedType {
                    onSelect(type)
                }
            } label: {
                Text("Continue")
                    .font(theme.bodyFont.weight(Font.Weight.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedType != nil ? theme.primaryColor : theme.primaryColor.opacity(0.5))
                    .cornerRadius(theme.cornerRadius)
            }
            .disabled(selectedType == nil)

            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(theme.bodyFont)
                    .foregroundColor(theme.secondaryTextColor)
            }
        }
        .padding(theme.padding)
    }

    private func documentSection(category: String, types: [DocumentType]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category)
                .font(theme.captionFont.weight(Font.Weight.semibold))
                .foregroundColor(theme.secondaryTextColor)
                .textCase(.uppercase)

            ForEach(types, id: \.self) { type in
                documentRow(type: type)
            }
        }
    }

    private func documentRow(type: DocumentType) -> some View {
        Button {
            selectedType = type
        } label: {
            HStack(spacing: 16) {
                Image(systemName: documentIcon(for: type))
                    .font(.system(size: 24))
                    .foregroundColor(theme.primaryColor)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(theme.bodyFont)
                        .foregroundColor(theme.textColor)

                    if type.requiresBack {
                        Text("Front and back required")
                            .font(theme.smallFont)
                            .foregroundColor(theme.secondaryTextColor)
                    }
                }

                Spacer()

                if selectedType == type {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(theme.primaryColor)
                } else {
                    Circle()
                        .stroke(theme.secondaryTextColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(selectedType == type ? theme.primaryColor.opacity(0.1) : theme.surfaceColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .stroke(selectedType == type ? theme.primaryColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var groupedDocuments: [String: [DocumentType]] {
        var groups: [String: [DocumentType]] = [:]

        for type in allowedTypes {
            let category = documentCategory(for: type)
            if groups[category] == nil {
                groups[category] = []
            }
            groups[category]?.append(type)
        }

        return groups
    }

    private func documentCategory(for type: DocumentType) -> String {
        switch type {
        case .usPassport, .usDriversLicense, .usStateId:
            return "United States"
        case .internationalPassport:
            return "International"
        case .ukPassport:
            return "United Kingdom"
        case .euIdGermany, .euIdFrance, .euIdSpain, .euIdItaly:
            return "European Union"
        case .ghanaCard, .nigeriaNin, .kenyaId, .southAfricaId:
            return "Africa"
        }
    }

    private func documentIcon(for type: DocumentType) -> String {
        switch type {
        case .usPassport, .internationalPassport, .ukPassport:
            return "book.closed.fill"
        case .usDriversLicense:
            return "car.fill"
        default:
            return "person.text.rectangle.fill"
        }
    }
}
