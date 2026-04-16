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

private enum AppRuntimeEnvironment {
    static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

private enum ModelContainerBootstrap {
    private static let logStore: RotatingRuntimeLogStore = {
        let store = RotatingRuntimeLogStore(
            logURL: DiagnosticsPaths.logFileURL(named: "model-container.log"),
            maxBytes: DiagnosticsLogLimits.compactMaxBytes
        )
        store.prepareForAppend(resetIfOversized: true)
        return store
    }()

    static func makeSharedContainer(isStoredInMemoryOnly: Bool = false) -> ModelContainer {
        let schema = Schema([
            Item.self,
        ])

        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)]
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
        logStore.appendLine("[\(ISO8601DateFormatter().string(from: Date()))] \(message)")
    }
}

private struct TestHostPlaceholderView: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 1, minHeight: 1)
    }
}

@main
struct O_PaperclipApp: App {
    init() {
        if !AppRuntimeEnvironment.isRunningTests {
            AppDiagnostics.shared.setupIfNeeded()
        }
    }

    var sharedModelContainer: ModelContainer = ModelContainerBootstrap.makeSharedContainer(
        isStoredInMemoryOnly: AppRuntimeEnvironment.isRunningTests
    )

    var body: some Scene {
        WindowGroup {
            if AppRuntimeEnvironment.isRunningTests {
                TestHostPlaceholderView()
            } else {
                ContentView()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
