//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import Dispatch
import PackageGraph
import PackageModel
import SourceControl

struct DeprecatedAPIDiff: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "experimental-api-diff",
                                                    abstract: "Deprecated - use `swift package diagnose-api-breaking-changes` instead",
                                                    shouldDisplay: false)

    @Argument(parsing: .captureForPassthrough)
    var args: [String] = []

    func run() throws {
        print("`swift package experimental-api-diff` has been renamed to `swift package diagnose-api-breaking-changes`")
        throw ExitCode.failure
    }
}

struct APIDiff: SwiftCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnose-api-breaking-changes",
        abstract: "Diagnose API-breaking changes to Swift modules in a package",
        discussion: """
        The diagnose-api-breaking-changes command can be used to compare the Swift API of \
        a package to a baseline revision, diagnosing any breaking changes which have \
        been introduced. By default, it compares every Swift module from the baseline \
        revision which is part of a library product. For packages with many targets, this \
        behavior may be undesirable as the comparison can be slow. \
        The `--products` and `--targets` options may be used to restrict the scope of \
        the comparison.
        """)

    @OptionGroup(visibility: .hidden)
    var globalOptions: GlobalOptions

    @Option(help: """
    The path to a text file containing breaking changes which should be ignored by the API comparison. \
    Each ignored breaking change in the file should appear on its own line and contain the exact message \
    to be ignored (e.g. 'API breakage: func foo() has been removed').
    """)
    var breakageAllowlistPath: AbsolutePath?

    @Argument(help: "The baseline treeish to compare to (e.g. a commit hash, branch name, tag, etc.)")
    var treeish: String

    @Option(parsing: .upToNextOption,
            help: "One or more products to include in the API comparison. If present, only the specified products (and any targets specified using `--targets`) will be compared.")
    var products: [String] = []

    @Option(parsing: .upToNextOption,
            help: "One or more targets to include in the API comparison. If present, only the specified targets (and any products specified using `--products`) will be compared.")
    var targets: [String] = []

    @Option(name: .customLong("baseline-dir"),
            help: "The path to a directory used to store API baseline files. If unspecified, a temporary directory will be used.")
    var overrideBaselineDir: AbsolutePath?

    @Flag(help: "Regenerate the API baseline, even if an existing one is available.")
    var regenerateBaseline: Bool = false

    func run(_ swiftTool: SwiftTool) throws {
        let apiDigesterPath = try swiftTool.getTargetToolchain().getSwiftAPIDigester()
        let apiDigesterTool = SwiftAPIDigester(fileSystem: swiftTool.fileSystem, tool: apiDigesterPath)

        let packageRoot = try globalOptions.locations.packageDirectory ?? swiftTool.getPackageRoot()
        let repository = GitRepository(path: packageRoot)
        let baselineRevision = try repository.resolveRevision(identifier: treeish)

        // We turn build manifest caching off because we need the build plan.
        let buildSystem = try swiftTool.createBuildSystem(explicitBuildSystem: .native, cacheBuildManifest: false)

        let packageGraph = try buildSystem.getPackageGraph()
        let modulesToDiff = try determineModulesToDiff(
            packageGraph: packageGraph,
            observabilityScope: swiftTool.observabilityScope
        )

        // Build the current package.
        try buildSystem.build()

        // Dump JSON for the baseline package.
        let baselineDumper = try APIDigesterBaselineDumper(
            baselineRevision: baselineRevision,
            packageRoot: swiftTool.getPackageRoot(),
            buildParameters: try buildSystem.buildPlan.buildParameters,
            apiDigesterTool: apiDigesterTool,
            observabilityScope: swiftTool.observabilityScope
        )

        let baselineDir = try baselineDumper.emitAPIBaseline(
            for: modulesToDiff,
            at: overrideBaselineDir,
            force: regenerateBaseline,
            logLevel: swiftTool.logLevel,
            swiftTool: swiftTool
        )

        let results = ThreadSafeArrayStore<SwiftAPIDigester.ComparisonResult>()
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: Int(try buildSystem.buildPlan.buildParameters.workers))
        var skippedModules: Set<String> = []

        for module in modulesToDiff {
            let moduleBaselinePath = baselineDir.appending("\(module).json")
            guard swiftTool.fileSystem.exists(moduleBaselinePath) else {
                print("\nSkipping \(module) because it does not exist in the baseline")
                skippedModules.insert(module)
                continue
            }
            semaphore.wait()
            DispatchQueue.sharedConcurrent.async(group: group) {
                do {
                    if let comparisonResult = try apiDigesterTool.compareAPIToBaseline(
                        at: moduleBaselinePath,
                        for: module,
                        buildPlan: try buildSystem.buildPlan,
                        except: breakageAllowlistPath
                    ) {
                        results.append(comparisonResult)
                    }
                } catch {
                    swiftTool.observabilityScope.emit(error: "failed to compare API to baseline", underlyingError: error)
                }
                semaphore.signal()
            }
        }

        group.wait()

        let failedModules = modulesToDiff
            .subtracting(skippedModules)
            .subtracting(results.map(\.moduleName))
        for failedModule in failedModules {
            swiftTool.observabilityScope.emit(error: "failed to read API digester output for \(failedModule)")
        }

        for result in results.get() {
            try self.printComparisonResult(result, observabilityScope: swiftTool.observabilityScope)
        }

        guard failedModules.isEmpty && results.get().allSatisfy(\.hasNoAPIBreakingChanges) else {
            throw ExitCode.failure
        }
    }

    private func determineModulesToDiff(packageGraph: PackageGraph, observabilityScope: ObservabilityScope) throws -> Set<String> {
        var modulesToDiff: Set<String> = []
        if products.isEmpty && targets.isEmpty {
            modulesToDiff.formUnion(packageGraph.apiDigesterModules)
        } else {
            for productName in products {
                guard let product = packageGraph
                        .rootPackages
                        .flatMap(\.products)
                        .first(where: { $0.name == productName }) else {
                    observabilityScope.emit(error: "no such product '\(productName)'")
                    continue
                }
                guard product.type.isLibrary else {
                    observabilityScope.emit(error: "'\(productName)' is not a library product")
                    continue
                }
                modulesToDiff.formUnion(product.targets.filter { $0.underlyingTarget is SwiftTarget }.map(\.c99name))
            }
            for targetName in targets {
                guard let target = packageGraph
                        .rootPackages
                        .flatMap(\.targets)
                        .first(where: { $0.name == targetName }) else {
                    observabilityScope.emit(error: "no such target '\(targetName)'")
                    continue
                }
                guard target.type == .library else {
                    observabilityScope.emit(error: "'\(targetName)' is not a library target")
                    continue
                }
                guard target.underlyingTarget is SwiftTarget else {
                    observabilityScope.emit(error: "'\(targetName)' is not a Swift language target")
                    continue
                }
                modulesToDiff.insert(target.c99name)
            }
            guard !observabilityScope.errorsReported else {
                throw ExitCode.failure
            }
        }
        return modulesToDiff
    }

    private func printComparisonResult(
        _ comparisonResult: SwiftAPIDigester.ComparisonResult,
        observabilityScope: ObservabilityScope
    ) throws {
        for diagnostic in comparisonResult.otherDiagnostics {
            let metadata = try diagnostic.location.map { location -> ObservabilityMetadata in
                var metadata = ObservabilityMetadata()
                metadata.fileLocation = .init(
                    try .init(validating: location.filename),
                    line: location.line < Int.max ? Int(location.line) : .none
                )
                return metadata
            }

            switch diagnostic.level {
            case .error, .fatal:
                observabilityScope.emit(error: diagnostic.text, metadata: metadata)
            case .warning:
                observabilityScope.emit(warning: diagnostic.text, metadata: metadata)
            case .note:
                observabilityScope.emit(info: diagnostic.text, metadata: metadata)
            case .remark:
                observabilityScope.emit(info: diagnostic.text, metadata: metadata)
            case .ignored:
                break
            }
        }

        let moduleName = comparisonResult.moduleName
        if comparisonResult.apiBreakingChanges.isEmpty {
            print("\nNo breaking changes detected in \(moduleName)")
        } else {
            let count = comparisonResult.apiBreakingChanges.count
            print("\n\(count) breaking \(count > 1 ? "changes" : "change") detected in \(moduleName):")
            for change in comparisonResult.apiBreakingChanges {
                print("  💔 \(change.text)")
            }
        }
    }
}
