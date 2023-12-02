//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.AbsolutePath
import struct LLBuildManifest.Node

extension LLBuildManifestBuilder {
    func createProductCommand(_ buildProduct: ProductBuildDescription) throws {
        let cmdName = try buildProduct.product.getCommandName(config: self.buildConfig)

        // Add dependency on Info.plist generation on Darwin platforms.
        let testInputs: [AbsolutePath]
        if buildProduct.product.type == .test
            && buildProduct.buildParameters.targetTriple.isDarwin()
            && buildProduct.buildParameters.testingParameters.experimentalTestOutput {
            let testBundleInfoPlistPath = try buildProduct.binaryPath.parentDirectory.parentDirectory.appending(component: "Info.plist")
            testInputs = [testBundleInfoPlistPath]

            self.manifest.addWriteInfoPlistCommand(
                principalClass: "\(buildProduct.product.targets[0].c99name).SwiftPMXCTestObserver",
                outputPath: testBundleInfoPlistPath
            )
        } else {
            testInputs = []
        }

        // Create a phony node to represent the entire target.
        let targetName = try buildProduct.product.getLLBuildTargetName(config: self.buildConfig)
        let output: Node = .virtual(targetName)

        let finalProductNode: Node
        switch buildProduct.product.type {
        case .library(.static):
            finalProductNode = try .file(buildProduct.binaryPath)
            try self.manifest.addShellCmd(
                name: cmdName,
                description: "Archiving \(buildProduct.binaryPath.prettyPath())",
                inputs: (buildProduct.objects + [buildProduct.linkFileListPath]).map(Node.file),
                outputs: [finalProductNode],
                arguments: try buildProduct.archiveArguments()
            )

        default:
            let inputs = try buildProduct.objects
                + buildProduct.dylibs.map { try $0.binaryPath }
                + [buildProduct.linkFileListPath]
                + testInputs

            let shouldCodeSign: Bool
            let linkedBinaryNode: Node
            let linkedBinaryPath = try buildProduct.binaryPath
            if case .executable = buildProduct.product.type,
               buildParameters.targetTriple.isMacOSX,
               buildParameters.debuggingParameters.shouldEnableDebuggingEntitlement {
                shouldCodeSign = true
                linkedBinaryNode = try .file(buildProduct.binaryPath, isMutated: true)
            } else {
                shouldCodeSign = false
                linkedBinaryNode = try .file(buildProduct.binaryPath)
            }

            try self.manifest.addShellCmd(
                name: cmdName,
                description: "Linking \(buildProduct.binaryPath.prettyPath())",
                inputs: inputs.map(Node.file),
                outputs: [linkedBinaryNode],
                arguments: try buildProduct.linkArguments()
            )

            if shouldCodeSign {
                let basename = try buildProduct.binaryPath.basename
                let plistPath = try buildProduct.binaryPath.parentDirectory
                    .appending(component: "\(basename)-entitlement.plist")
                self.manifest.addEntitlementPlistCommand(
                    entitlement: "com.apple.security.get-task-allow",
                    outputPath: plistPath
                )

                let cmdName = try buildProduct.product.getCommandName(config: self.buildConfig)
                let codeSigningOutput = Node.virtual(targetName + "-CodeSigning")
                try self.manifest.addShellCmd(
                    name: "\(cmdName)-entitlements",
                    description: "Applying debug entitlements to \(buildProduct.binaryPath.prettyPath())",
                    inputs: [linkedBinaryNode, .file(plistPath)],
                    outputs: [codeSigningOutput],
                    arguments: buildProduct.codeSigningArguments(plistPath: plistPath, binaryPath: linkedBinaryPath)
                )
                finalProductNode = codeSigningOutput
            } else {
                finalProductNode = linkedBinaryNode
            }
        }

        self.manifest.addNode(output, toTarget: targetName)
        self.manifest.addPhonyCmd(
            name: output.name,
            inputs: [finalProductNode],
            outputs: [output]
        )

        if self.plan.graph.reachableProducts.contains(buildProduct.product) {
            if buildProduct.product.type != .test {
                self.addNode(output, toTarget: .main)
            }
            self.addNode(output, toTarget: .test)
        }

        self.manifest.addWriteLinkFileListCommand(
            objects: Array(buildProduct.objects),
            linkFileListPath: buildProduct.linkFileListPath
        )
    }
}
