//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageModel
import Workspace

import struct TSCBasic.ByteString
import class TSCBasic.Process
import struct TSCBasic.StringError
import struct TSCUtility.SerializedDiagnostics

#if os(macOS)
private func macOSBundleRoot() throws -> AbsolutePath {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        return try AbsolutePath(validating: bundle.bundlePath).parentDirectory
    }
    fatalError()
}
#endif

private func resolveBinDir() throws -> AbsolutePath {
#if os(macOS)
    return try macOSBundleRoot()
#else
    return try AbsolutePath(validating: CommandLine.arguments[0], relativeTo: localFileSystem.currentWorkingDirectory!).parentDirectory
#endif
}

extension SwiftSDK {
    public static var `default`: Self {
        get throws {
            let binDir = try resolveBinDir()
            return try! SwiftSDK.hostSwiftSDK(binDir)
        }
    }
}

extension UserToolchain {
    public static var `default`: Self {
        get throws {
            return try .init(swiftSDK: SwiftSDK.default)
        }
    }
}

extension UserToolchain {
    /// Helper function to determine if async await actually works in the current environment.
    public func supportsSwiftConcurrency() -> Bool {
      #if os(macOS)
        if #available(macOS 12.0, *) {
            // On macOS 12 and later, concurrency is assumed to work.
            return true
        }
        else {
            // On macOS 11 and earlier, we don't know if concurrency actually works because not all SDKs and toolchains have the right bits.  We could examine the SDK and the various libraries, but the most accurate test is to just try to compile and run a snippet of code that requires async/await support.  It doesn't have to actually do anything, it's enough that all the libraries can be found (but because the library reference is weak we do need the linkage reference to `_swift_task_create` and the like).
            do {
                try testWithTemporaryDirectory { tmpPath in
                    let inputPath = tmpPath.appending("foo.swift")
                    try localFileSystem.writeFileContents(inputPath, string: "public func foo() async {}\nTask { await foo() }")
                    let outputPath = tmpPath.appending("foo")
                    let toolchainPath = self.swiftCompilerPath.parentDirectory.parentDirectory
                    let backDeploymentLibPath = toolchainPath.appending(components: "lib", "swift-5.5", "macosx")
                    try Process.checkNonZeroExit(arguments: ["/usr/bin/xcrun", "--toolchain", toolchainPath.pathString, "swiftc", inputPath.pathString, "-Xlinker", "-rpath", "-Xlinker", backDeploymentLibPath.pathString, "-o", outputPath.pathString])
                    try Process.checkNonZeroExit(arguments: [outputPath.pathString])
                }
            } catch {
                // On any failure we assume false.
                return false
            }
            // If we get this far we could compile and run a trivial executable that uses libConcurrency, so we can say that this toolchain supports concurrency on this host.
            return true
        }
      #else
        // On other platforms, concurrency is assumed to work since with new enough versions of the toolchain.
        return true
      #endif
    }

    /// Helper function to determine whether serialized diagnostics work properly in the current environment.
    public func supportsSerializedDiagnostics(otherSwiftFlags: [String] = []) -> Bool {
        do {
            try testWithTemporaryDirectory { tmpPath in
                let inputPath = tmpPath.appending("best.swift")
                try localFileSystem.writeFileContents(inputPath, string: "func foo() -> Bool {\nvar unused: Int\nreturn true\n}\n")
                let outputPath = tmpPath.appending("foo")
                let serializedDiagnosticsPath = tmpPath.appending("out.dia")
                let toolchainPath = self.swiftCompilerPath.parentDirectory.parentDirectory
                try Process.checkNonZeroExit(arguments: ["/usr/bin/xcrun", "--toolchain", toolchainPath.pathString, "swiftc", inputPath.pathString, "-Xfrontend", "-serialize-diagnostics-path", "-Xfrontend", serializedDiagnosticsPath.pathString, "-g", "-o", outputPath.pathString] + otherSwiftFlags)
                try Process.checkNonZeroExit(arguments: [outputPath.pathString])

                let diaFileContents = try localFileSystem.readFileContents(serializedDiagnosticsPath)
                let diagnosticsSet = try SerializedDiagnostics(bytes: diaFileContents)
                if diagnosticsSet.diagnostics.isEmpty {
                    throw StringError("does not support diagnostics")
                }
            }
            return true
        } catch {
            return false
        }
    }

    public func supportsSuppressWarnings() -> Bool {
        do {
            try testWithTemporaryDirectory { tmpPath in
                let inputPath = tmpPath.appending("best.swift")
                try localFileSystem.writeFileContents(inputPath, string: "let foo: String? = \"bar\"\nprint(foo)\n")
                let outputPath = tmpPath.appending("foo")
                let serializedDiagnosticsPath = tmpPath.appending("out.dia")
                let toolchainPath = self.swiftCompilerPath.parentDirectory.parentDirectory
                try Process.checkNonZeroExit(arguments: ["/usr/bin/xcrun", "--toolchain", toolchainPath.pathString, "swiftc", inputPath.pathString, "-Xfrontend", "-serialize-diagnostics-path", "-Xfrontend", serializedDiagnosticsPath.pathString, "-o", outputPath.pathString, "-suppress-warnings"])

                let diaFileContents = try localFileSystem.readFileContents(serializedDiagnosticsPath)
                let diagnosticsSet = try SerializedDiagnostics(bytes: diaFileContents)

                if diagnosticsSet.diagnostics.contains(where: { $0.text.contains("warning") }) {
                    throw StringError("does not support suppressing warnings")
                }
            }
            return true
        } catch {
            return false
        }
    }

    // This builds a trivial program with `-warnings-as-errors`, if it fails, the compiler in use generates warnings by default and is not suitable for testing warnings as errors behaviors.
    public func supportsWarningsAsErrors() -> Bool {
        do {
            try testWithTemporaryDirectory { tmpPath in
                let inputPath = tmpPath.appending("best.swift")
                try localFileSystem.writeFileContents(inputPath, string: "print(\"hello\")")
                let outputPath = tmpPath.appending("foo")
                let toolchainPath = self.swiftCompilerPath.parentDirectory.parentDirectory
                try Process.checkNonZeroExit(arguments: ["/usr/bin/xcrun", "--toolchain", toolchainPath.pathString, "swiftc", inputPath.pathString, "-o", outputPath.pathString, "-warnings-as-errors"])
            }
            return true
        } catch {
            return false
        }
    }

    /// Helper function to determine whether we should run SDK-dependent tests.
    public func supportsSDKDependentTests() -> Bool {
        return ProcessInfo.processInfo.environment["SWIFTCI_DISABLE_SDK_DEPENDENT_TESTS"] == nil
    }
}
