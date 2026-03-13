import Foundation

/// Response from GET /api/v1/document-types
struct DocumentTypesResponse: Decodable {
    let success: Bool
    let documentTypes: [APIDocumentTypeInfo]
    let total: Int
    let countries: [APICountryInfo]
}

/// Document type info returned by the API
struct APIDocumentTypeInfo: Decodable {
    let type: String
    let name: String
    let country: String
    let hasMrz: Bool
    let requiresBack: Bool
    let supportedOcr: Bool
}

/// Country info returned by the API
struct APICountryInfo: Decodable {
    let code: String
    let name: String
    let region: String?
}

// MARK: - Conversion to SDK types

extension APICountryInfo {
    /// Convert API country info to the SDK's CountryInfo, attaching the
    /// document types that belong to this country.
    func toCountryInfo(documentTypes: [APIDocumentTypeInfo], configuredTypes: [DocumentType]) -> CountryInfo {
        // Map API document type strings to SDK DocumentType enum values.
        // Unknown types (not in the enum) are silently skipped so the SDK
        // remains forward-compatible when the backend adds new types.
        let countryDocTypes = documentTypes
            .filter { $0.country == code }
            .compactMap { DocumentType(rawValue: $0.type) }
            .filter { configuredTypes.contains($0) }

        return CountryInfo(
            id: code,
            name: name,
            flagEmoji: Self.flagEmoji(for: code),
            documentTypes: countryDocTypes
        )
    }

    /// Convert an ISO 3166-1 alpha-2 country code to a flag emoji.
    static func flagEmoji(for countryCode: String) -> String {
        let base: UInt32 = 127397 // Regional Indicator Symbol Letter A minus ASCII 'A'
        return countryCode
            .uppercased()
            .unicodeScalars
            .compactMap { UnicodeScalar(base + $0.value) }
            .map { String($0) }
            .joined()
    }
}
