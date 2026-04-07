import Foundation
import MapKit
import Combine

@MainActor
final class LocationSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate, LocationSearching {
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var completerError: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }

    func updateQuery(_ query: String, region: MKCoordinateRegion?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completions = []
            completerError = nil
            completer.queryFragment = ""
            return
        }

        if let region {
            completer.region = region
        }
        completer.queryFragment = trimmed
    }

    func clearSuggestions() {
        completions = []
        completerError = nil
        completer.queryFragment = ""
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = Array(completer.results.prefix(AppConstants.Search.maxCompletionResults))
        completerError = nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completions = []
        completerError = error.localizedDescription
    }

    func search(for query: String, region: MKCoordinateRegion?) async throws -> [MKMapItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let region {
            request.region = region
        }
        let response = try await MKLocalSearch(request: request).start()
        return ranked(response.mapItems, query: trimmed, region: region)
    }

    func search(for completion: MKLocalSearchCompletion, region: MKCoordinateRegion?) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request(completion: completion)
        if let region {
            request.region = region
        }
        let response = try await MKLocalSearch(request: request).start()
        return ranked(response.mapItems, query: completion.title, region: region)
    }

    private func ranked(_ items: [MKMapItem], query: String, region: MKCoordinateRegion?) -> [MKMapItem] {
        let referenceLocation = region.map {
            CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude)
        }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let deduped = items.reduce(into: [String: MKMapItem]()) { partialResult, item in
            partialResult[dedupeKey(for: item)] = item
        }.values

        return deduped.sorted { lhs, rhs in
            let lhsRank = rankingScore(for: lhs, query: normalizedQuery)
            let rhsRank = rankingScore(for: rhs, query: normalizedQuery)
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            let lhsDistance = distance(for: lhs, from: referenceLocation)
            let rhsDistance = distance(for: rhs, from: referenceLocation)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }

            return (lhs.name ?? "").localizedStandardCompare(rhs.name ?? "") == .orderedAscending
        }
    }

    private func rankingScore(for item: MKMapItem, query: String) -> Int {
        guard !query.isEmpty else { return 3 }
        let name = (item.name ?? "").lowercased()
        let address = item.paperclipAddressSearchText

        if name == query { return 0 }
        if name.hasPrefix(query) { return 1 }
        if name.contains(query) { return 2 }
        if address.contains(query) { return 3 }
        return item.pointOfInterestCategory == nil ? 5 : 4
    }

    private func distance(for item: MKMapItem, from reference: CLLocation?) -> CLLocationDistance {
        guard let reference else { return .greatestFiniteMagnitude }
        guard let location = item.paperclipLocation else { return .greatestFiniteMagnitude }
        return reference.distance(from: location)
    }

    private func dedupeKey(for item: MKMapItem) -> String {
        let coordinate = item.paperclipCoordinate ?? .init()
        let name = item.name ?? ""
        return "\(name.lowercased())|\(coordinate.latitude)|\(coordinate.longitude)"
    }
}
