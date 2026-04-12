import SwiftUI
import MapKit

struct LocationInputSectionView: View {
    @Bindable var vm: AppViewModel
    let currentRegion: MKCoordinateRegion?
    let onImportGPX: () -> Void
    let onUseImportedRoute: (ImportedGPXRoute) -> Void
    let onFocusImportedRoute: (ImportedGPXRoute) -> Void
    let onRemoveImportedRoute: (ImportedGPXRoute) -> Void

    var body: some View {
        if vm.operationMode == .fixedRoute {
            fixedRouteHintSection
        } else {
            standardLocationInputSection
        }
    }

    private var fixedRouteHintSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("位置輸入").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)
            Text("固定路線的匯入與選擇已移到右側「匯入與收藏」欄位。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var standardLocationInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("位置輸入").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)

            SearchBar(placeKeyword: $vm.placeKeyword, onSearch: { vm.searchPlaces(currentRegion: currentRegion) })

            if let completerError = vm.locationSearchService.completerError {
                Text(completerError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if !vm.locationSearchService.completions.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(vm.locationSearchService.completions.enumerated()), id: \.offset) { _, completion in
                            Button(action: { vm.searchPlaces(using: completion, currentRegion: currentRegion) }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .frame(maxHeight: 132)
            }

            if !vm.placeResults.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(vm.placeResults.prefix(8).enumerated()), id: \.offset) { _, item in
                            Button(action: {
                                vm.placeKeyword = item.name ?? vm.placeKeyword
                                if let coordinate = vm.coordinate(for: item) {
                                    vm.insertPoint(coordinate)
                                }
                            }) {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "location.fill")
                                        .foregroundColor(ModernTheme.accent)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(item.name ?? "Unknown Place")
                                            if let category = item.pointOfInterestCategory {
                                                Text(category.rawValue.replacingOccurrences(of: "_", with: " "))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }

                                        let subtitle = vm.searchResultSubtitle(for: item)
                                        if !subtitle.isEmpty {
                                            Text(subtitle)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer(minLength: 8)

                                    if let distanceText = vm.searchResultDistanceText(for: item, cameraRegion: currentRegion) {
                                        Text(distanceText)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }

            HStack(spacing: 6) {
                TextField(
                    "",
                    text: $vm.coordinateInputText,
                    prompt: Text("請輸入：35.6621161,139.6986385").foregroundColor(.secondary)
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { vm.insertCoordinateFromInput() }
                Button("確認") { vm.insertCoordinateFromInput() }
                    .buttonStyle(.borderedProminent)
                    .tint(ModernTheme.accent)
                    .controlSize(.small)
            }

            if let err = vm.locationInputError, !err.isEmpty {
                Text(err).font(.caption).foregroundColor(.red)
            }
        }
    }
}
