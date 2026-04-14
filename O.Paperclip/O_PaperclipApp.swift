//
//  O_PaperclipApp.swift
//  O.Paperclip
//
//  Created by Mason Yen on 3/2/26.
//

import AppIntents
import Foundation
import SwiftUI
import SwiftData

private enum ModelContainerBootstrap {
    private static let logURL = DiagnosticsPaths.logFileURL(named: "model-container.log")

    static func makeSharedContainer() -> ModelContainer {
        let schema = Schema([
            Item.self,
        ])

        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
            )
        } catch {
            appendLog("persistent-store 初始化失敗，改用 in-memory fallback：\(error.localizedDescription)")
        }

        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        } catch {
            appendLog("in-memory fallback 初始化失敗：\(error.localizedDescription)")
            fatalError("Could not create fallback ModelContainer: \(error)")
        }
    }

    private static func appendLog(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? data.write(to: logURL, options: .atomic)
            }
            return
        }

        try? data.write(to: logURL, options: .atomic)
    }
}

@main
struct O_PaperclipApp: App {
    init() {
        AppDiagnostics.shared.setupIfNeeded()
    }

    var sharedModelContainer: ModelContainer = ModelContainerBootstrap.makeSharedContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
