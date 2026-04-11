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
    var sentCoordinates: [CLLocationCoordinate2D] = []
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
    var startContinuousLocationStreamCallCount: Int = 0
    var stopContinuousLocationStreamCallCount: Int = 0
    var clearSimulatedLocationCallCount: Int = 0

    func connect() {}
    func connectDevice() {}
    func disconnect() {}
    func sendCoordinate(latitude: Double, longitude: Double) {}
    func sendLocationToDevice(latitude: Double, longitude: Double) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        lastSentCoordinate = coordinate
        sentCoordinates.append(coordinate)
    }
    func startContinuousLocationStream() {
        startContinuousLocationStreamCallCount += 1
    }
    func stopContinuousLocationStream() {
        stopContinuousLocationStreamCallCount += 1
    }
    func clearSimulatedLocation() {
        clearSimulatedLocationCallCount += 1
    }
    func connectDeviceAsync() async throws {}
    func disconnectAsync() async {}
    func sendLocationToDeviceAsync(latitude: Double, longitude: Double) async throws {}
    func clearSimulatedLocationAsync() async throws {
        clearSimulatedLocationCallCount += 1
    }
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

    @Test func parsesGroupedRemoteBrowseJSONIdentifiers() throws {
        let raw = """
        {
          "usb": [
            {
              "UniqueDeviceID": "USB-DEVICE-1234"
            }
          ],
          "wifi": [
            {
              "identifier": "WIFI-DEVICE-5678"
            }
          ]
        }
        """

        let identifiers = RemoteBrowseOutputParser.identifiers(in: raw)

        #expect(identifiers == ["WIFI-DEVICE-5678", "USB-DEVICE-1234"])
    }

    @Test func deduplicatesRemoteBrowseIdentifiers() throws {
        let raw = """
        {
          "wifi": [
            {
              "identifier": "DUPLICATED-DEVICE"
            }
          ],
          "devices": [
            {
              "Identifier": "DUPLICATED-DEVICE"
            }
          ]
        }
        """

        let identifiers = RemoteBrowseOutputParser.identifiers(in: raw)

        #expect(identifiers == ["DUPLICATED-DEVICE"])
    }

    @Test func helperRegistryRoundTripsManagedRecord() throws {
        let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let registry = HelperProcessRegistry(directoryURL: directoryURL)

        let helperID = registry.register(
            sessionID: "session-123",
            kind: .privilegedTunnel,
            pid: 321,
            parentPID: 654,
            childPID: 987,
            startedAt: "2026-04-10T00:00:00Z",
            pidFileURL: URL(fileURLWithPath: "/tmp/helper.pid"),
            stopFileURL: URL(fileURLWithPath: "/tmp/helper.stop"),
            command: "privileged-tunnel-helper"
        )

        let records = registry.records()
        #expect(records.count == 1)
        #expect(records.first?.helperID == helperID)
        #expect(records.first?.kind == .privilegedTunnel)
        #expect(records.first?.pid == 321)
        #expect(records.first?.childPID == 987)
        #expect(records.first?.pidFilePath == "/tmp/helper.pid")
        #expect(records.first?.stopFilePath == "/tmp/helper.stop")
        #expect(records.first?.command == "privileged-tunnel-helper")

        registry.unregister(helperID: helperID)
        #expect(registry.records().isEmpty)

        try? FileManager.default.removeItem(at: directoryURL)
    }

    @Test func managedHelperRecordParsesCommandWithEquals() throws {
        let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let recordURL = directoryURL.appendingPathComponent("helper.state")
        let raw = """
        helperID=helper
        sessionID=session
        kind=tunnel
        pid=42
        command=--flag=value
        """
        try raw.write(to: recordURL, atomically: true, encoding: .utf8)

        let record = ManagedHelperRecord.load(from: recordURL)

        #expect(record?.helperID == "helper")
        #expect(record?.kind == .tunnel)
        #expect(record?.command == "--flag=value")

        try? FileManager.default.removeItem(at: directoryURL)
    }

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

    @Test func remoteBrowseParserReadsIdentifiersFromJSON() {
        let raw = """
        [
          {"identifier":"0000111122223333444455556666777788889999","hostname":"iphone.local"},
          {"Identifier":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","Hostname":"ipad.local"}
        ]
        """

        #expect(
            RemoteBrowseOutputParser.identifiers(in: raw) == [
                "0000111122223333444455556666777788889999",
                "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            ]
        )
    }

    @Test func remoteBrowseParserReadsIdentifiersFromTextOutput() {
        let raw = """
        DEVICE 1
        IDENTIFIER:0000111122223333444455556666777788889999
        DEVICE 2
        IDENTIFIER:AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
        """

        #expect(
            RemoteBrowseOutputParser.identifiers(in: raw) == [
                "0000111122223333444455556666777788889999",
                "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            ]
        )
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

    @Test func joystickMotionEngineNormalizesDiagonalVector() {
        let vector = JoystickMotionEngine.normalizedVector(for: [.up, .right])

        #expect(abs(vector.dx - 0.7071067) < 0.0001)
        #expect(abs(vector.dy - 0.7071067) < 0.0001)
        #expect(abs(hypot(vector.dx, vector.dy) - 1.0) < 0.0001)
    }

    @Test func joystickMotionEngineEastMovementUsesLatitude() {
        let equator = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let highLatitude = CLLocationCoordinate2D(latitude: 60, longitude: 0)

        let equatorMoved = JoystickMotionEngine.translatedCoordinate(from: equator, northMeters: 0, eastMeters: 10)
        let highLatitudeMoved = JoystickMotionEngine.translatedCoordinate(from: highLatitude, northMeters: 0, eastMeters: 10)

        #expect(abs(equatorMoved.longitude) > 0)
        #expect(abs(highLatitudeMoved.longitude) > abs(equatorMoved.longitude))
    }

    @Test func gpxParserReadsTracksAndRoutes() throws {
        let data = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <name>河濱軌跡</name>
            <trkseg>
              <trkpt lat="25.0330" lon="121.5654" />
              <trkpt lat="25.0340" lon="121.5664" />
            </trkseg>
            <trkseg>
              <trkpt lat="25.0350" lon="121.5674" />
            </trkseg>
          </trk>
          <rte>
            <name>巷弄路線</name>
            <rtept lat="25.0400" lon="121.5700" />
            <rtept lat="25.0410" lon="121.5710" />
          </rte>
        </gpx>
        """.data(using: .utf8)!

        let routes = try GPXRouteParser.parse(
            data: data,
            fallbackTitle: "fallback",
            sourceName: "route.gpx",
            stableIDPrefix: "preview-test",
            sourceFilePath: "/tmp/route.gpx"
        )

        #expect(routes.count == 2)
        #expect(routes[0].title == "河濱軌跡")
        #expect(routes[0].points.count == 3)
        #expect(routes[1].title == "巷弄路線")
        #expect(routes[1].points.count == 2)
    }

    @Test func gpxParserIgnoresRoutesWithTooFewPoints() throws {
        let data = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <name>短路線</name>
            <trkseg>
              <trkpt lat="25.0330" lon="121.5654" />
            </trkseg>
          </trk>
          <rte>
            <rtept lat="25.0400" lon="121.5700" />
            <rtept lat="25.0410" lon="121.5710" />
          </rte>
        </gpx>
        """.data(using: .utf8)!

        let routes = try GPXRouteParser.parse(
            data: data,
            fallbackTitle: "fallback",
            sourceName: "route.gpx",
            stableIDPrefix: "preview-test",
            sourceFilePath: "/tmp/route.gpx"
        )

        #expect(routes.count == 1)
        #expect(routes[0].points.count == 2)
    }

    @Test func importedGPXRouteStorePersistsAndReloadsRoutes() throws {
        ImportedGPXRouteStore.savePaths([])
        ImportedGPXRouteStore.saveTitleOverrides([:])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            ImportedGPXRouteStore.savePaths([])
            ImportedGPXRouteStore.saveTitleOverrides([:])
            try? FileManager.default.removeItem(at: tempDir)
        }

        let gpxURL = tempDir.appendingPathComponent("sample.gpx")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <name>測試固定路線</name>
            <trkseg>
              <trkpt lat="25.0330" lon="121.5654" />
              <trkpt lat="25.0340" lon="121.5664" />
            </trkseg>
          </trk>
        </gpx>
        """.write(to: gpxURL, atomically: true, encoding: .utf8)

        let previewRoutes = try ImportedGPXRouteStore.previewRoutes(from: [gpxURL])
        let persistedRoutes = try ImportedGPXRouteStore.persistImportedRoutes([
            previewRoutes[0].renamed(to: "自訂固定路線")
        ])

        let storedPaths = persistedRoutes.compactMap(\.sourceFilePath)
        ImportedGPXRouteStore.savePaths(storedPaths)
        ImportedGPXRouteStore.saveTitleOverrides(Dictionary(uniqueKeysWithValues: storedPaths.map { ($0, "自訂固定路線") }))

        let loadedRoutes = ImportedGPXRouteStore.loadRoutes()

        #expect(loadedRoutes.count == 1)
        #expect(loadedRoutes[0].title == "自訂固定路線")
        #expect(loadedRoutes[0].points.count == 2)

        persistedRoutes.compactMap(\.sourceFilePath).forEach {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: $0))
        }
    }

    @MainActor
    @Test func joystickSessionMovesAndStopsAtPinnedLocation() {
        let deviceManager = MockDeviceManager()
        deviceManager.isConnected = true

        let vm = AppViewModel(
            deviceManager: deviceManager,
            locationSearchService: MockLocationSearchService()
        )

        let start = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
        vm.operationMode = .joystick
        vm.insertPoint(start)
        vm.handleMainAction()

        #expect(vm.activeOperationMode == .joystick)
        #expect(vm.isJoystickSessionActive)
        #expect(vm.currentPosition?.latitude == start.latitude)

        vm.updateJoystickDirection(.up, isPressed: true)
        vm.stepJoystickMovement(elapsedTime: AppConstants.Simulation.joystickTimerInterval)

        let moved = vm.currentPosition
        #expect(vm.appState == .moving)
        #expect((moved?.latitude ?? 0) > start.latitude)

        vm.updateJoystickDirection(.up, isPressed: false)
        let stopped = vm.currentPosition
        vm.stepJoystickMovement(elapsedTime: AppConstants.Simulation.joystickTimerInterval)

        #expect(vm.appState == .readyToMove)
        #expect(abs((vm.currentPosition?.latitude ?? 0) - (stopped?.latitude ?? 0)) < 0.0000001)
    }

    @MainActor
    @Test func endingJoystickSessionClearsActiveState() {
        let deviceManager = MockDeviceManager()
        deviceManager.isConnected = true

        let vm = AppViewModel(
            deviceManager: deviceManager,
            locationSearchService: MockLocationSearchService()
        )

        vm.operationMode = .joystick
        vm.insertPoint(CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654))
        vm.handleMainAction()
        vm.handleMainAction()

        #expect(!vm.isJoystickSessionActive)
        #expect(vm.currentPosition == nil)
        #expect(vm.appState == .selectingA)
        #expect(deviceManager.clearSimulatedLocationCallCount == 1)
    }

    @MainActor
    @Test func selectingImportedGPXRouteBuildsDraftAndUsesReplacementFlow() {
        let deviceManager = MockDeviceManager()
        deviceManager.isConnected = true

        let vm = AppViewModel(
            deviceManager: deviceManager,
            locationSearchService: MockLocationSearchService()
        )

        vm.operationMode = .joystick
        vm.insertPoint(CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654))
        vm.handleMainAction()

        let route = ImportedGPXRoute(
            id: "preview-route",
            title: "固定路線",
            sourceName: "sample.gpx",
            points: [
                CLLocationCoordinate2D(latitude: 25.0400, longitude: 121.5700),
                CLLocationCoordinate2D(latitude: 25.0410, longitude: 121.5710)
            ],
            totalDistance: 150,
            sourceFilePath: "/tmp/sample.gpx",
            sourceRouteID: "trk-0"
        )

        vm.operationMode = .fixedRoute
        vm.useImportedGPXRoute(route)

        #expect(vm.selectedImportedGPXRouteID == route.id)
        #expect(vm.draftRoutePoints.count == 2)
        #expect(vm.appState == .readyToMove)

        vm.handleMainAction()

        #expect(vm.isShowingRouteReplacementConfirmation)
    }

    @MainActor
    @Test func importedGPXRouteCanStartSimulation() {
        let deviceManager = MockDeviceManager()
        deviceManager.isConnected = true

        let vm = AppViewModel(
            deviceManager: deviceManager,
            locationSearchService: MockLocationSearchService()
        )

        let route = ImportedGPXRoute(
            id: "preview-route",
            title: "固定路線",
            sourceName: "sample.gpx",
            points: [
                CLLocationCoordinate2D(latitude: 25.0400, longitude: 121.5700),
                CLLocationCoordinate2D(latitude: 25.0410, longitude: 121.5710)
            ],
            totalDistance: 150,
            sourceFilePath: "/tmp/sample.gpx",
            sourceRouteID: "trk-0"
        )

        vm.operationMode = .fixedRoute
        vm.useImportedGPXRoute(route)
        vm.handleMainAction()

        #expect(vm.activeOperationMode == .fixedRoute)
        #expect(vm.isActiveSimulationRunning)
        #expect(vm.activeRoutePolyline != nil)
    }
}
