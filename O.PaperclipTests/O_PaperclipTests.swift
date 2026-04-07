import Foundation
import Combine
import MapKit
import Testing
@testable import O_Paperclip

private final class MockDeviceManager: DeviceControlling {
    let objectWillChange = ObservableObjectPublisher()

    var connectionState: DeviceConnectionState = .disconnected
    var logEntries: [String] { debugLog }
    var lastSentCoordinate: CLLocationCoordinate2D?
    var debugLog: [String] = []
    var isConnected: Bool = false
    var isConnecting: Bool = false
    var connectionStage: String = ""
    var deviceName: String = "測試裝置"
    var lastError: String?
    var manualRsdHost: String = ""
    var manualRsdPort: String = ""
    var tunnelUDID: String = ""
    var isWirelessMode: Bool = false

    func connect() {}
    func connectDevice() {}
    func disconnect() {}
    func sendCoordinate(latitude: Double, longitude: Double) {}
    func sendLocationToDevice(latitude: Double, longitude: Double) {}
    func startContinuousLocationStream() {}
    func stopContinuousLocationStream() {}
    func clearSimulatedLocation() {}
    func connectDeviceAsync() async throws {}
    func disconnectAsync() async {}
    func sendLocationToDeviceAsync(latitude: Double, longitude: Double) async throws {}
    func clearSimulatedLocationAsync() async throws {}
}

@MainActor
private final class MockLocationSearchService: LocationSearching {
    let objectWillChange = ObservableObjectPublisher()
    var completions: [MKLocalSearchCompletion] = []
    var completerError: String?

    func updateQuery(_ query: String, region: MKCoordinateRegion?) {}
    func clearSuggestions() {}
    func search(for query: String, region: MKCoordinateRegion?) async throws -> [MKMapItem] { [] }
    func search(for completion: MKLocalSearchCompletion, region: MKCoordinateRegion?) async throws -> [MKMapItem] { [] }
}

private struct MockRouteCalculator: RouteCalculating {
    let handler: (MKDirections.Request, @escaping (MKDirections.Response?, (any Error)?) -> Void) -> Void

    func calculate(
        request: MKDirections.Request,
        completion: @escaping (MKDirections.Response?, (any Error)?) -> Void
    ) {
        handler(request, completion)
    }
}

struct O_PaperclipTests {

    @Test func parsesDirectKMLIntoOverlay() throws {
        let data = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>台北純點</name>
            <Style id="coffee-style">
              <IconStyle>
                <color>ff007cf5</color>
              </IconStyle>
            </Style>
            <StyleMap id="coffee-map">
              <Pair>
                <key>normal</key>
                <styleUrl>#coffee-style</styleUrl>
              </Pair>
            </StyleMap>
            <Folder>
              <name>咖啡杯 義式餐廳 拉麵 餐廳</name>
              <Placemark>
                <name>咖啡杯（已確認是純點）</name>
                <styleUrl>#coffee-map</styleUrl>
                <Point>
                  <coordinates>121.5654,25.0330,0</coordinates>
                </Point>
              </Placemark>
            </Folder>
          </Document>
        </kml>
        """.data(using: .utf8)!

        let overlay = try PurePointKMLParser.parse(
            data: data,
            fallbackTitle: "fallback",
            sourceName: "taipei.kml",
            stableID: "test-overlay",
            sourceFilePath: "/tmp/taipei.kml"
        )

        #expect(overlay.title == "台北純點")
        #expect(overlay.points.count == 1)
        #expect(overlay.points.first?.categoryID == "咖啡杯")
        #expect(overlay.categories.first?.colorHex == "F57C00")
    }

    @Test func rejectsFileSchemeNetworkLink() throws {
        let linkedURL = URL(fileURLWithPath: "/tmp/inner.kml")
        let data = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <NetworkLink>
              <Link>
                <href>\(linkedURL.absoluteString)</href>
              </Link>
            </NetworkLink>
          </Document>
        </kml>
        """.data(using: .utf8)!

        var caughtError: PurePointImportError?
        do {
            _ = try PurePointKMLResolver.resolveKMLData(from: data, baseURL: nil)
        } catch let error as PurePointImportError {
            caughtError = error
        }

        guard let caughtError else {
            #expect(false)
            return
        }

        guard case .unsupportedRemoteScheme(let href) = caughtError else {
            #expect(false)
            return
        }
        #expect(href.contains("file://"))
    }

    @Test func requiresApprovalForHTTPSNetworkLink() throws {
        let remoteURL = URL(string: "https://example.com/points.kml")!
        let data = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <NetworkLink>
              <Link>
                <href>\(remoteURL.absoluteString)</href>
              </Link>
            </NetworkLink>
          </Document>
        </kml>
        """.data(using: .utf8)!

        var caughtError: PurePointImportError?
        do {
            _ = try PurePointKMLResolver.resolveKMLData(from: data, baseURL: nil)
        } catch let error as PurePointImportError {
            caughtError = error
        }

        guard let caughtError else {
            #expect(false)
            return
        }

        guard case .remoteLinkRequiresApproval(let urls) = caughtError else {
            #expect(false)
            return
        }
        #expect(urls == [remoteURL])
    }

    @Test func resolvesApprovedHTTPSNetworkLink() throws {
        let remoteURL = URL(string: "https://example.com/points.kml")!
        let outerData = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <NetworkLink>
              <Link>
                <href>\(remoteURL.absoluteString)</href>
              </Link>
            </NetworkLink>
          </Document>
        </kml>
        """.data(using: .utf8)!

        let innerData = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <Placemark>
              <name>公車（已確認是純點）</name>
              <Point>
                <coordinates>121.5000,25.0400,0</coordinates>
              </Point>
            </Placemark>
          </Document>
        </kml>
        """.data(using: .utf8)!

        let resolved = try PurePointKMLResolver.resolveKMLData(
            from: outerData,
            baseURL: nil,
            approvedRemoteURLs: Set([remoteURL]),
            remoteFetcher: { _ in innerData }
        )
        let overlay = try PurePointKMLParser.parse(
            data: resolved,
            fallbackTitle: "wrapper",
            sourceName: "outer.kml",
            stableID: "linked-overlay",
            sourceFilePath: "/tmp/outer.kml"
        )

        #expect(overlay.points.count == 1)
        #expect(overlay.points.first?.categoryID == "公車")
    }

    @Test func relativeHTTPSLinkAlsoRequiresApproval() throws {
        let baseURL = URL(string: "https://example.com/folder/outer.kml")!
        let expectedURL = URL(string: "https://example.com/folder/inner.kml")!
        let data = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <NetworkLink>
              <Link>
                <href>inner.kml</href>
              </Link>
            </NetworkLink>
          </Document>
        </kml>
        """.data(using: .utf8)!

        var caughtError: PurePointImportError?
        do {
            _ = try PurePointKMLResolver.resolveKMLData(from: data, baseURL: baseURL)
        } catch let error as PurePointImportError {
            caughtError = error
        }

        guard let caughtError else {
            #expect(false)
            return
        }

        guard case .remoteLinkRequiresApproval(let urls) = caughtError else {
            #expect(false)
            return
        }
        #expect(urls == [expectedURL])
    }

    @Test func batchPreviewStopsForRemoteApproval() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let directURL = tempDir.appendingPathComponent("direct.kml")
        let outerURL = tempDir.appendingPathComponent("outer.kml")
        let remoteURL = URL(string: "https://example.com/linked.kml")!

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>direct</name>
            <Placemark>
              <name>公車（已確認是純點）</name>
              <Point>
                <coordinates>121.5000,25.0400,0</coordinates>
              </Point>
            </Placemark>
          </Document>
        </kml>
        """.write(to: directURL, atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>wrapper</name>
            <NetworkLink>
              <name>linked</name>
              <Link>
                <href><![CDATA[
        \(remoteURL.absoluteString)
                ]]></href>
              </Link>
            </NetworkLink>
          </Document>
        </kml>
        """.write(to: outerURL, atomically: true, encoding: .utf8)

        var caughtError: PurePointImportError?
        do {
            _ = try ImportedPurePointOverlayStore.previewOverlays(from: [directURL, outerURL])
        } catch let error as PurePointImportError {
            caughtError = error
        }

        guard let caughtError else {
            #expect(false)
            return
        }

        guard case .remoteLinkRequiresApproval(let urls) = caughtError else {
            #expect(false)
            return
        }
        #expect(urls == [remoteURL])
    }

    @Test func pidParserOnlyAcceptsPositiveIntegers() {
        #expect(PrivilegedTunnelPIDParser.parse("123\n") == 123)
        #expect(PrivilegedTunnelPIDParser.parse("0") == nil)
        #expect(PrivilegedTunnelPIDParser.parse("-5") == nil)
        #expect(PrivilegedTunnelPIDParser.parse("1; rm -rf /") == nil)
    }

    @Test func deviceLogRedactorMasksSensitiveValues() {
        let udid = "0000111122223333444455556666777788889999"
        let message = "指定 UDID \(udid) 連線到 RSD endpoint: 127.0.0.1:12345，定位 25.033033, 121.565400"
        let sanitizedMessage = DeviceLogRedactor.sanitizedMessage(message)
        let sanitizedCommand = DeviceLogRedactor.sanitizedCommandString([
            "developer", "simulate-location", "set",
            "--rsd", "127.0.0.1", "12345",
            "--udid", udid,
            "--", "25.033033", "121.565400"
        ])

        #expect(sanitizedMessage.contains("0000...9999"))
        #expect(!sanitizedMessage.contains(udid))
        #expect(!sanitizedMessage.contains("127.0.0.1:12345"))
        #expect(sanitizedMessage.contains("25.0330, 121.5654"))
        #expect(sanitizedCommand.contains("--udid 0000...9999"))
        #expect(sanitizedCommand.contains("--rsd [RSD_HOST] [RSD_PORT]"))
        #expect(sanitizedCommand.contains("-- 25.0330 121.5654"))
    }

    @Test func runtimeLogStoreRotatesWhenExceedingLimit() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logURL = tempDir.appendingPathComponent("device-runtime.log")
        let store = RotatingRuntimeLogStore(logURL: logURL, maxBytes: 32)

        store.appendLine("12345678901234567890")
        store.appendLine("abcdefghijklmnopqrst")

        let backupURL = logURL.deletingLastPathComponent().appendingPathComponent("device-runtime.log.1")
        let currentText = try String(contentsOf: logURL, encoding: .utf8)
        let backupText = try String(contentsOf: backupURL, encoding: .utf8)

        #expect(currentText.contains("abcdefghijklmnopqrst"))
        #expect(backupText.contains("12345678901234567890"))
    }

    @MainActor
    @Test func routeABFailureShowsRecoverableError() {
        let vm = AppViewModel(
            deviceManager: MockDeviceManager(),
            locationSearchService: MockLocationSearchService(),
            routeCalculator: MockRouteCalculator { _, completion in
                completion(nil, NSError(domain: "Test", code: -1))
            }
        )

        vm.operationMode = .routeAB
        vm.pointA = CLLocationCoordinate2D(latitude: 25.033, longitude: 121.5654)
        vm.pointB = CLLocationCoordinate2D(latitude: 25.037, longitude: 121.5637)
        vm.appState = .calculatingRoute

        vm.calculateRoutes()

        #expect(vm.appState == .selectingB)
        #expect(vm.locationInputError == "A 到 B 路線計算失敗，請調整起點或終點後再試。")
    }

    @MainActor
    @Test func multiPointFailureReturnsToSelectionWithError() {
        let vm = AppViewModel(
            deviceManager: MockDeviceManager(),
            locationSearchService: MockLocationSearchService(),
            routeCalculator: MockRouteCalculator { _, completion in
                completion(nil, NSError(domain: "Test", code: -2))
            }
        )

        vm.operationMode = .multiPoint
        vm.waypoints = [
            CLLocationCoordinate2D(latitude: 25.033, longitude: 121.5654),
            CLLocationCoordinate2D(latitude: 25.037, longitude: 121.5637)
        ]

        vm.calculateMultiPointRoute()

        #expect(vm.appState == .selectingA)
        #expect(vm.locationInputError == "第 1 段路線計算失敗，請調整選點後再試。")
    }
}
