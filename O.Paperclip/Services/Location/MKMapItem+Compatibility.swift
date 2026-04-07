import Foundation
import MapKit

extension MKMapItem {
    var paperclipLocation: CLLocation? {
        if #available(macOS 26.0, *) {
            return location
        }
        return placemark.location
    }

    var paperclipCoordinate: CLLocationCoordinate2D? {
        paperclipLocation?.coordinate
    }

    var paperclipAddressSummary: String {
        if #available(macOS 26.0, *) {
            if let representation = addressRepresentations {
                return representation.fullAddress(includingRegion: false, singleLine: true)
                    ?? representation.cityWithContext(.automatic)
                    ?? ""
            }
            if let address {
                return address.shortAddress ?? address.fullAddress
            }
        }
        return placemark.paperclipAddressSummary
    }

    var paperclipAddressSearchText: String {
        if #available(macOS 26.0, *) {
            return [
                address?.shortAddress,
                address?.fullAddress,
                addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        }
        return placemark.paperclipAddressSearchText
    }
}

extension MKPlacemark {
    var paperclipAddressSummary: String {
        let parts = [
            subThoroughfare,
            thoroughfare,
            subLocality,
            locality,
            administrativeArea,
            postalCode,
            country
        ]
        .compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }

        let fallback = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallback
    }

    var paperclipAddressSearchText: String {
        paperclipAddressSummary.lowercased()
    }
}
