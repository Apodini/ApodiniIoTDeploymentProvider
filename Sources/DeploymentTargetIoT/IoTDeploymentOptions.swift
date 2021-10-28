//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//       

import ArgumentParser
import Foundation

/// Contains all options that are required by the `IotDeploymentProvider`.
public struct IoTDeploymentOptions: ParsableArguments {
    @Option(help: "The type ids that should be searched for")
    public var types: String = "_workstation._tcp."

    @Option(help: "Directory containing the Package.swift with the to-be-deployed web service's target")
    public var inputPackageDir: String = "/Users/felice/Documents/ApodiniDemoWebService"

    @Option(help: "Name of the web service's SPM target/product")
    public var productName: String = "TestWebService"

    @Option(help: "Remote directory of deployment")
    public var deploymentDir: String = "/usr/deployment"

    @Flag(help: "If set, the deployment provider listens for changes in the working directory and automatically redeploys them."
    )
    public var automaticRedeploy = false
    
    @Option(help: "The port the web service will listen on")
    public var port: Int = 8080
    
    @Option(help: "The interval stating how frequent the provider tries to redeploy")
    public var redeploymentInterval: Int = 30
    
    @Flag(help: "Dumps the log of the provider to /Log in the format <timeStamp>_<executableName>_dump.log")
    public var dumpLog = false
    
    public init() {}
}
