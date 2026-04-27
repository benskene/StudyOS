//
//  ModelContainerProvider.swift
//  Struc
//
//  Created by Ben Skene on 2/2/26.
//

import Foundation
import SwiftData

#if canImport(SwiftUI)
import SwiftUI
#endif

/// Provides configured SwiftData `ModelContainer` instances for app/runtime, previews, and tests.
struct ModelContainerProvider {
    /// The default store name on disk. Adjust if you split stores by feature.
    private static let storeName = "Struc.store"

    /// Optional: override the store location (useful for app group containers, etc.).
    /// If `nil`, SwiftData chooses a default path in Application Support.
    private static let storeURLOverride: URL? = nil

    /// Compute a configuration using our schema and storage options.
    private static func configuration(for schema: Schema, inMemory: Bool) -> ModelConfiguration {
        if inMemory {
            return ModelConfiguration(isStoredInMemoryOnly: true)
        }

        if let overrideURL = storeURLOverride {
            let url = overrideURL.appendingPathComponent(storeName, isDirectory: false)
            return ModelConfiguration(url: url)
        } else {
            // Provide a stable filename to make artifacts easier to manage.
            return ModelConfiguration(storeName)
        }
    }

    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = appSchema
        let config = configuration(for: schema, inMemory: inMemory)

        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            guard !inMemory else {
                fatalError("Unable to create in-memory ModelContainer: \(error)")
            }

            // Log some diagnostics to help identify store incompatibilities.
            #if DEBUG
            print("[ModelContainerProvider] Initial container creation failed: \(error)")
            if case let error as NSError = error {
                print("[ModelContainerProvider] domain=\(error.domain) code=\(error.code) userInfo=\(error.userInfo)")
            }
            #endif

            // Recover from incompatible local schema by clearing old store artifacts.
            clearLocalStoreArtifacts()

            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Unable to create ModelContainer after reset: \(error)")
            }
        }
    }

    /// Convenience container for SwiftUI previews or unit tests.
    /// Optionally seeds the store with sample data via the provided closure.
    static func makeInMemory(seed: ((ModelContext) throws -> Void)? = nil) -> ModelContainer {
        let container = make(inMemory: true)
        if let seed {
            let context = ModelContext(container)
            do {
                try seed(context)
                try context.save()
            } catch {
                #if DEBUG
                print("[ModelContainerProvider] Seeding in-memory store failed: \(error)")
                #endif
            }
        }
        return container
    }

    /// A convenience schema definition in one place for reuse.
    private static var appSchema: Schema {
        Schema([
            Assignment.self,
            FocusSprint.self,
            DailyPlanItem.self,
            ConsistencySnapshot.self,
            SyncEvent.self
        ])
    }

    private static func clearLocalStoreArtifacts() {
        let fileManager = FileManager.default
        let candidateDirectories = [
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        let baseNames = [storeName.replacingOccurrences(of: ".store", with: ""), "Struc"]
        let removableSuffixes = [
            ".store", ".store-shm", ".store-wal",
            ".sqlite", ".sqlite-shm", ".sqlite-wal"
        ]

        for directory in candidateDirectories {
            guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                let path = fileURL.lastPathComponent.lowercased()
                let isTarget = baseNames.contains { base in
                    let lower = base.lowercased()
                    return path.hasPrefix(lower) && removableSuffixes.contains { suffix in path.hasSuffix(suffix) }
                }
                guard isTarget else { continue }
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    #if canImport(SwiftUI)
    /// Injects a `ModelContainer` into a SwiftUI view hierarchy.
    /// Usage: MyRootView().modelContainer(ModelContainerProvider.make())
    static func attach(to view: some View, inMemory: Bool = false) -> some View {
        let container = make(inMemory: inMemory)
        return view.modelContainer(container)
    }
    #endif
}

