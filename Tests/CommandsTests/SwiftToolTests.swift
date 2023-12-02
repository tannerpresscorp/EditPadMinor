//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import Basics
@testable import Build
@testable import CoreCommands
@testable import Commands
@testable import PackageModel
import SPMTestSupport
import XCTest

import class TSCBasic.BufferedOutputByteStream
import class TSCBasic.InMemoryFileSystem
import protocol TSCBasic.OutputByteStream
import var TSCBasic.stderrStream

final class SwiftToolTests: CommandsTestCase {
    func testVerbosityLogLevel() throws {
        try fixture(name: "Miscellaneous/Simple") { fixturePath in
            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString])
                let tool = try SwiftTool.createSwiftToolForTest(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .warning)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--verbose"])
                let tool = try SwiftTool.createSwiftToolForTest(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .info)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "-v"])
                let tool = try SwiftTool.createSwiftToolForTest(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .info)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--very-verbose"])
                let tool = try SwiftTool.createSwiftToolForTest(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .debug)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--vv"])
                let tool = try SwiftTool.createSwiftToolForTest(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .debug)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--quiet"])
                let tool = try SwiftTool.createSwiftToolForTest(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .error)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }

            do {
                let outputStream = BufferedOutputByteStream()
                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "-q"])
                let tool = try SwiftTool.createSwiftToolForTest(outputStream: outputStream, options: options)
                XCTAssertEqual(tool.logLevel, .error)

                tool.observabilityScope.emit(error: "error")
                tool.observabilityScope.emit(warning: "warning")
                tool.observabilityScope.emit(info: "info")
                tool.observabilityScope.emit(debug: "debug")

                tool.waitForObservabilityEvents(timeout: .now() + .seconds(1))

                XCTAssertMatch(outputStream.bytes.validDescription, .contains("error: error"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("warning: warning"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("info: info"))
                XCTAssertNoMatch(outputStream.bytes.validDescription, .contains("debug: debug"))
            }
        }
    }

    func testAuthorizationProviders() throws {
        try fixture(name: "DependencyResolution/External/XCFramework") { fixturePath in
            let fs = localFileSystem

            // custom .netrc file
            do {
                let customPath = try fs.tempDirectory.appending(component: UUID().uuidString)
                try fs.writeFileContents(
                    customPath,
                    string: "machine mymachine.labkey.org login custom@labkey.org password custom"
                )

                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--netrc-file", customPath.pathString])
                let tool = try SwiftTool.createSwiftToolForTest(options: options)

                let authorizationProvider = try tool.getAuthorizationProvider() as? CompositeAuthorizationProvider
                let netrcProviders = authorizationProvider?.providers.compactMap { $0 as? NetrcAuthorizationProvider } ?? []
                XCTAssertEqual(netrcProviders.count, 1)
                XCTAssertEqual(try netrcProviders.first.map { try resolveSymlinks($0.path) }, try resolveSymlinks(customPath))

                let auth = try tool.getAuthorizationProvider()?.authentication(for: "https://mymachine.labkey.org")
                XCTAssertEqual(auth?.user, "custom@labkey.org")
                XCTAssertEqual(auth?.password, "custom")

                // delete it
                try localFileSystem.removeFileTree(customPath)
                XCTAssertThrowsError(try tool.getAuthorizationProvider(), "error expected") { error in
                    XCTAssertEqual(error as? StringError, StringError("Did not find netrc file at \(customPath)."))
                }
            }

            // Tests should not modify user's home dir .netrc so leaving that out intentionally
        }
    }

    func testRegistryAuthorizationProviders() throws {
        try fixture(name: "DependencyResolution/External/XCFramework") { fixturePath in
            let fs = localFileSystem

            // custom .netrc file
            do {
                let customPath = try fs.tempDirectory.appending(component: UUID().uuidString)
                try fs.writeFileContents(
                    customPath,
                    string: "machine mymachine.labkey.org login custom@labkey.org password custom"
                )

                let options = try GlobalOptions.parse(["--package-path", fixturePath.pathString, "--netrc-file", customPath.pathString])
                let tool = try SwiftTool.createSwiftToolForTest(options: options)

                // There is only one AuthorizationProvider depending on platform
                #if canImport(Security)
                let keychainProvider = try tool.getRegistryAuthorizationProvider() as? KeychainAuthorizationProvider
                XCTAssertNotNil(keychainProvider)
                #else
                let netrcProvider = try tool.getRegistryAuthorizationProvider() as? NetrcAuthorizationProvider
                XCTAssertNotNil(netrcProvider)
                XCTAssertEqual(try netrcProvider.map { try resolveSymlinks($0.path) }, try resolveSymlinks(customPath))

                let auth = try tool.getRegistryAuthorizationProvider()?.authentication(for: "https://mymachine.labkey.org")
                XCTAssertEqual(auth?.user, "custom@labkey.org")
                XCTAssertEqual(auth?.password, "custom")

                // delete it
                try localFileSystem.removeFileTree(customPath)
                XCTAssertThrowsError(try tool.getRegistryAuthorizationProvider(), "error expected") { error in
                    XCTAssertEqual(error as? StringError, StringError("did not find netrc file at \(customPath)"))
                }
                #endif
            }

            // Tests should not modify user's home dir .netrc so leaving that out intentionally
        }
    }

    func testDebugFormatFlags() throws {
        let fs = InMemoryFileSystem(emptyFiles: [
            "/Pkg/Sources/exe/main.swift",
        ])

        let observer = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(fileSystem: fs, manifests: [
                Manifest.createRootManifest(displayName: "Pkg",
                                            path: "/Pkg",
                                            targets: [TargetDescription(name: "exe")])
        ], observabilityScope: observer.topScope)

        var plan: BuildPlan


        /* -debug-info-format dwarf */
        let explicitDwarfOptions = try GlobalOptions.parse(["--triple", "x86_64-unknown-windows-msvc", "-debug-info-format", "dwarf"])
        let explicitDwarf = try SwiftTool.createSwiftToolForTest(options: explicitDwarfOptions)
        plan = try BuildPlan(
            buildParameters: explicitDwarf.buildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observer.topScope
        )
        try XCTAssertMatch(plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? [],
                           [.anySequence, "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf"])


        /* -debug-info-format codeview */
        let explicitCodeViewOptions = try GlobalOptions.parse(["--triple", "x86_64-unknown-windows-msvc", "-debug-info-format", "codeview"])
        let explicitCodeView = try SwiftTool.createSwiftToolForTest(options: explicitCodeViewOptions)

        plan = try BuildPlan(
            buildParameters: explicitCodeView.buildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observer.topScope
        )
        try XCTAssertMatch(plan.buildProducts.compactMap { $0 as?  Build.ProductBuildDescription }.first?.linkArguments() ?? [],
                           [.anySequence, "-g", "-debug-info-format=codeview", "-Xlinker", "-debug"])

        // Explicitly pass Linux as when the SwiftTool tests are enabled on
        // Windows, this would fail otherwise as CodeView is supported on the
        // native host.
        let unsupportedCodeViewOptions = try GlobalOptions.parse(["--triple", "x86_64-unknown-linux-gnu", "-debug-info-format", "codeview"])
        let unsupportedCodeView = try SwiftTool.createSwiftToolForTest(options: unsupportedCodeViewOptions)

        XCTAssertThrowsError(try unsupportedCodeView.buildParameters()) {
            XCTAssertEqual($0 as? StringError, StringError("CodeView debug information is currently not supported on linux"))
        }

        /* <<null>> */
        let implicitDwarfOptions = try GlobalOptions.parse(["--triple", "x86_64-unknown-windows-msvc"])
        let implicitDwarf = try SwiftTool.createSwiftToolForTest(options: implicitDwarfOptions)
        plan = try BuildPlan(
            buildParameters: implicitDwarf.buildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observer.topScope
        )
        try XCTAssertMatch(plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? [],
                           [.anySequence, "-g", "-use-ld=lld", "-Xlinker", "-debug:dwarf"])

        /* -debug-info-format none */
        let explicitNoDebugInfoOptions = try GlobalOptions.parse(["--triple", "x86_64-unknown-windows-msvc", "-debug-info-format", "none"])
        let explicitNoDebugInfo = try SwiftTool.createSwiftToolForTest(options: explicitNoDebugInfoOptions)
        plan = try BuildPlan(
            buildParameters: explicitNoDebugInfo.buildParameters(),
            graph: graph,
            fileSystem: fs,
            observabilityScope: observer.topScope
        )
        try XCTAssertMatch(plan.buildProducts.compactMap { $0 as? Build.ProductBuildDescription }.first?.linkArguments() ?? [],
                           [.anySequence, "-gnone", .anySequence])
    }
}

extension SwiftTool {
    static func createSwiftToolForTest(
        outputStream: OutputByteStream = stderrStream,
        options: GlobalOptions
    ) throws -> SwiftTool {
        return try SwiftTool(
            outputStream: outputStream,
            options: options,
            toolWorkspaceConfiguration: .init(shouldInstallSignalHandlers: false),
            workspaceDelegateProvider: {
                ToolWorkspaceDelegate(
                    observabilityScope: $0,
                    outputHandler: $1,
                    progressHandler: $2,
                    inputHandler: $3
                )
            },
            workspaceLoaderProvider: {
                XcodeWorkspaceLoader(
                    fileSystem: $0,
                    observabilityScope: $1
                )
            })
    }
}
