import Foundation
import Testing
@testable import O_Paperclip

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
        #expect(overlay.points.first?.categoryID == "Coffee Cup")
        #expect(overlay.categories.first?.colorHex == "F57C00")
    }

    @Test func resolvesNetworkLinkedKML() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let innerURL = tempDir.appendingPathComponent("inner.kml")
        let outerURL = tempDir.appendingPathComponent("outer.kml")

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>linked</name>
            <Placemark>
              <name>公車（已確認是純點）</name>
              <Point>
                <coordinates>121.5000,25.0400,0</coordinates>
              </Point>
            </Placemark>
          </Document>
        </kml>
        """.write(to: innerURL, atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>wrapper</name>
            <NetworkLink>
              <name>linked</name>
              <Link>
                <href><![CDATA[
        \(innerURL.absoluteString)
                ]]></href>
              </Link>
            </NetworkLink>
          </Document>
        </kml>
        """.write(to: outerURL, atomically: true, encoding: .utf8)

        let resolved = try PurePointKMLResolver.resolveKMLData(from: Data(contentsOf: outerURL), baseURL: outerURL)
        let overlay = try PurePointKMLParser.parse(
            data: resolved,
            fallbackTitle: "wrapper",
            sourceName: "outer.kml",
            stableID: "linked-overlay",
            sourceFilePath: outerURL.path
        )

        #expect(overlay.points.count == 1)
        #expect(overlay.points.first?.categoryID == "Bus")
    }
}
