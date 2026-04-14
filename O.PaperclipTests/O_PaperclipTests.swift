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
    var connectionNotice: String?
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

    @Test func parsesIOSUSBIdentifiersFromIORegOutput() throws {
        let raw = """
        +-o USB2 Hub@02100000  <class IOUSBHostDevice, id 0x100000a36, registered>
          {
            "kUSBSerialNumberString" = "7423J07"
            "USB Product Name" = "USB2 Hub"
          }
        +-o iPhone@03100000  <class IOUSBHostDevice, id 0x10019324e, registered>
          {
            "kUSBSerialNumberString" = "00008150001220E23C84401C"
            "USB Product Name" = "iPhone"
            "SupportsIPhoneOS" = Yes
          }
        +-o iPad@04100000  <class IOUSBHostDevice, id 0x10019324f, registered>
          {
            "kUSBSerialNumberString" = "000081010000112233445566"
            "kUSBProductString" = "iPad"
            "SupportsIPhoneOS" = Yes
          }
        """

        let identifiers = USBHardwareProbeParser.identifiers(in: raw)

        #expect(identifiers == [
            "00008150001220E23C84401C",
            "000081010000112233445566"
        ])
    }

    @Test func matchesDashedAndUndashedDeviceIdentifiers() {
        #expect(
            DeviceIdentifierNormalizer.matches(
                "00008150-001220E23C84401C",
                "00008150001220E23C84401C"
            )
        )
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
            Issue.record("預期應攔截到不支援的遠端連結錯誤，但實際上沒有拋錯")
            return
        }

        guard case .unsupportedRemoteScheme(let href) = caughtError else {
            Issue.record("預期為 unsupportedRemoteScheme，實際為 \(String(describing: caughtError))")
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
            Issue.record("預期應要求遠端連結審核，但實際上沒有拋錯")
            return
        }

        guard case .remoteLinkRequiresApproval(let urls) = caughtError else {
            Issue.record("預期為 remoteLinkRequiresApproval，實際為 \(String(describing: caughtError))")
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
            Issue.record("預期相對 HTTPS 連結需要審核，但實際上沒有拋錯")
            return
        }

        guard case .remoteLinkRequiresApproval(let urls) = caughtError else {
            Issue.record("預期為 remoteLinkRequiresApproval，實際為 \(String(describing: caughtError))")
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
            Issue.record("預期批次預覽會要求遠端審核，但實際上沒有拋錯")
            return
        }

        guard case .remoteLinkRequiresApproval(let urls) = caughtError else {
            Issue.record("預期為 remoteLinkRequiresApproval，實際為 \(String(describing: caughtError))")
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

    @MainActor
    @Test func confirmingRouteReplacementKeepsContinuousStreamAlive() {
        let deviceManager = MockDeviceManager()
        deviceManager.isConnected = true

        let vm = AppViewModel(
            deviceManager: deviceManager,
            locationSearchService: MockLocationSearchService()
        )

        let firstRoute = ImportedGPXRoute(
            id: "route-1",
            title: "第一條",
            sourceName: "a.gpx",
            points: [
                CLLocationCoordinate2D(latitude: 25.0400, longitude: 121.5700),
                CLLocationCoordinate2D(latitude: 25.0410, longitude: 121.5710)
            ],
            totalDistance: 150,
            sourceFilePath: "/tmp/a.gpx",
            sourceRouteID: "trk-0"
        )
        let secondRoute = ImportedGPXRoute(
            id: "route-2",
            title: "第二條",
            sourceName: "b.gpx",
            points: [
                CLLocationCoordinate2D(latitude: 25.0500, longitude: 121.5800),
                CLLocationCoordinate2D(latitude: 25.0510, longitude: 121.5810)
            ],
            totalDistance: 160,
            sourceFilePath: "/tmp/b.gpx",
            sourceRouteID: "trk-1"
        )

        vm.operationMode = .fixedRoute
        vm.useImportedGPXRoute(firstRoute)
        vm.handleMainAction()

        #expect(vm.isActiveSimulationRunning)
        #expect(deviceManager.stopContinuousLocationStreamCallCount == 0)

        vm.useImportedGPXRoute(secondRoute)
        vm.confirmRouteReplacement()

        #expect(vm.activeOperationMode == .fixedRoute)
        #expect(vm.currentRoutePoints.count == secondRoute.points.count)
        #expect(vm.currentRoutePoints.first?.latitude == secondRoute.points.first?.latitude)
        #expect(vm.currentRoutePoints.last?.longitude == secondRoute.points.last?.longitude)
        #expect(vm.isActiveSimulationRunning)
        #expect(deviceManager.stopContinuousLocationStreamCallCount == 0)
    }

    @MainActor
    @Test func savesPinnedLocationAndCanApplyItAgain() throws {
        let deviceManager = MockDeviceManager()
        let vm = AppViewModel(
            deviceManager: deviceManager,
            locationSearchService: MockLocationSearchService()
        )

        let coordinate = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
        vm.operationMode = .fixedPoint
        vm.insertPoint(coordinate)
        vm.prepareSaveCurrentSelection()
        vm.pendingSavedLocationTitle = "台北車站"
        vm.confirmSaveCurrentSelection()

        guard let saved = vm.savedLocations.first(where: { $0.title == "台北車站" }) else {
            Issue.record("找不到剛儲存的收藏項目")
            return
        }

        #expect(saved.kind == .point)
        #expect(saved.coordinates.count == 1)

        vm.resetAll()
        vm.applySavedLocation(saved)

        #expect(vm.operationMode == .fixedPoint)
        #expect(vm.appState == .readyToMove)
        #expect(vm.pointA?.latitude == coordinate.latitude)
        #expect(vm.pointA?.longitude == coordinate.longitude)

        vm.removeSavedLocation(saved)
    }

    @MainActor
    @Test func savePreviewUsesDraftSourceForReadyPoint() throws {
        let vm = AppViewModel(
            deviceManager: MockDeviceManager(),
            locationSearchService: MockLocationSearchService()
        )

        vm.operationMode = .fixedPoint
        vm.insertPoint(CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654))

        let preview = vm.currentSavableItemPreview

        #expect(preview.isAvailable)
        #expect(preview.kind == .point)
        #expect(preview.sourceLabel == "已完成草稿")
        #expect(preview.actionTitle == "儲存這個定點")
        #expect(preview.summaryText.contains("座標"))
    }

    @MainActor
    @Test func savePreviewUsesActiveSourceForRunningRoute() throws {
        let vm = AppViewModel(
            deviceManager: MockDeviceManager(),
            locationSearchService: MockLocationSearchService()
        )

        vm.activeOperationMode = .fixedRoute
        vm.currentRoutePoints = [
            CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
            CLLocationCoordinate2D(latitude: 25.0340, longitude: 121.5664)
        ]
        vm.totalRouteDistance = 240
        var coordinates = vm.currentRoutePoints
        vm.activeRoutePolyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)

        let preview = vm.currentSavableItemPreview

        #expect(preview.isAvailable)
        #expect(preview.kind == .route)
        #expect(preview.sourceLabel == "活動中的內容")
        #expect(preview.actionTitle == "儲存這條線路")
        #expect(preview.summaryText.contains("2 點"))
    }

    @MainActor
    @Test func applyingSavedABRoutePreservesLoadedDraftAcrossModeChange() throws {
        let vm = AppViewModel(
            deviceManager: MockDeviceManager(),
            locationSearchService: MockLocationSearchService()
        )

        vm.operationMode = .joystick

        let item = SavedLocationItem(
            id: "saved-ab",
            title: "A-B 收藏",
            kind: .route,
            coordinates: [
                CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
                CLLocationCoordinate2D(latitude: 25.0340, longitude: 121.5664),
                CLLocationCoordinate2D(latitude: 25.0350, longitude: 121.5674)
            ],
            totalDistance: 320,
            createdAt: Date(),
            regionGroup: .taiwan,
            sourceMode: OperationMode.routeAB.rawValue,
            sourceFilePath: "/tmp/saved-ab.json"
        )

        vm.applySavedLocation(item)

        if !vm.consumeProgrammaticModeResetSuppression() {
            vm.switchModePreservingPinnedLocation()
        }

        #expect(vm.operationMode == .routeAB)
        #expect(vm.appState == .readyToMove)
        #expect(vm.pointA?.latitude == item.coordinates.first?.latitude)
        #expect(vm.pointB?.longitude == item.coordinates.last?.longitude)
        #expect(vm.draftRoutePoints.count == item.coordinates.count)
    }

    @MainActor
    @Test func applyingSavedFixedRouteMapsToMultiPoint() throws {
        let vm = AppViewModel(
            deviceManager: MockDeviceManager(),
            locationSearchService: MockLocationSearchService()
        )

        let item = SavedLocationItem(
            id: "saved-fixed-route",
            title: "固定路線收藏",
            kind: .route,
            coordinates: [
                CLLocationCoordinate2D(latitude: 25.0400, longitude: 121.5700),
                CLLocationCoordinate2D(latitude: 25.0410, longitude: 121.5710)
            ],
            totalDistance: 180,
            createdAt: Date(),
            regionGroup: .taiwan,
            sourceMode: OperationMode.fixedRoute.rawValue,
            sourceFilePath: "/tmp/saved-fixed-route.json"
        )

        vm.applySavedLocation(item)

        #expect(vm.operationMode == .multiPoint)
        #expect(vm.appState == .readyToMove)
        #expect(vm.isClosedLoop == false)
        #expect(vm.draftRoutePoints.count == 2)
    }

    @MainActor
    @Test func applyingSavedLoopMapsToClosedMultiPoint() throws {
        let vm = AppViewModel(
            deviceManager: MockDeviceManager(),
            locationSearchService: MockLocationSearchService()
        )

        let loopStart = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
        let item = SavedLocationItem(
            id: "saved-loop",
            title: "閉圈收藏",
            kind: .loop,
            coordinates: [
                loopStart,
                CLLocationCoordinate2D(latitude: 25.0340, longitude: 121.5664),
                loopStart
            ],
            totalDistance: 420,
            createdAt: Date(),
            regionGroup: .taiwan,
            sourceMode: OperationMode.multiPoint.rawValue,
            sourceFilePath: "/tmp/saved-loop.json"
        )

        vm.isEndlessLoop = true
        vm.applySavedLocation(item)

        #expect(vm.operationMode == .multiPoint)
        #expect(vm.isClosedLoop)
        #expect(vm.isEndlessLoop == false)
        #expect(vm.draftRoutePoints.first?.latitude == loopStart.latitude)
    }

    @MainActor
    @Test func activeTravelTimeSummaryUsesRemainingDistance() throws {
        let vm = AppViewModel(
            deviceManager: MockDeviceManager(),
            locationSearchService: MockLocationSearchService()
        )

        vm.speed = 6.0
        vm.activeOperationMode = .fixedRoute
        vm.currentRoutePoints = [
            CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
            CLLocationCoordinate2D(latitude: 25.0340, longitude: 121.5664)
        ]
        vm.totalRouteDistance = 600
        vm.traveledDistance = 120
        var coordinates = vm.currentRoutePoints
        vm.activeRoutePolyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)

        let summary = vm.travelTimeSummary

        #expect(summary?.label == "剩餘")
        #expect(summary?.distance == 480)
        #expect(summary?.timeText == "4 分 48 秒")
    }

    @MainActor
    @Test func closedLoopEndpointMarkersCollapseIntoSingleMarker() throws {
        let vm = AppViewModel(
            deviceManager: MockDeviceManager(),
            locationSearchService: MockLocationSearchService()
        )

        let start = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
        vm.operationMode = .multiPoint
        vm.isClosedLoop = true
        vm.draftRoutePoints = [
            start,
            CLLocationCoordinate2D(latitude: 25.0340, longitude: 121.5664),
            start
        ]

        let draftMarkers = vm.draftRouteEndpointMarkers

        #expect(draftMarkers.count == 1)
        #expect(draftMarkers.first?.title == "草稿起點／終點")
    }
}
