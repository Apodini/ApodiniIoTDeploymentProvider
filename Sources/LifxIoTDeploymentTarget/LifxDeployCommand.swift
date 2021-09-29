//
//  File.swift
//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//  

import ArgumentParser
import DeploymentTargetIoTCommon
import DeploymentTargetIoT
import DeviceDiscovery
import LifxDiscoveryActions
import LifxIoTDeploymentOption
import Foundation

struct LifxDeployCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "deploy",
            abstract: "LIFX Deployment Provider",
            discussion: "Runs the LIFX deployment provider",
            version: "0.0.1"
        )
    }
    
    @Argument(parsing: .unconditionalRemaining, help: "CLI arguments of the web service")
    var webServiceArguments: [String] = []
    
    @OptionGroup
    var deploymentOptions: IoTDeploymentOptions
    
    func run() throws {
        let provider = IoTDeploymentProvider(
            searchableTypes: deploymentOptions.types.split(separator: ",").map(String.init),
            productName: deploymentOptions.productName,
            packageRootDir: deploymentOptions.inputPackageDir,
            deploymentDir: deploymentOptions.deploymentDir,
            automaticRedeployment: deploymentOptions.automaticRedeploy,
            additionalConfiguration: [
                .deploymentDirectory: deploymentOptions.deploymentDir
            ],
            webServiceArguments: webServiceArguments,
            //            input: .dockerImage("hendesi/master-thesis:latest-arm64"),
            //            input: .package(LIFXDeviceDiscoveryAction.self)
            input: .dockerCompose(
                fileURL: URL(fileURLWithPath: "/Users/felice/Documents/ApodiniDemoWebService/docker-compose.yml"),
                serviceName: "apodini-test-web-service",
                containerName: "test"
            ),
            configurationFile: URL(fileURLWithPath: "/Users/felice/Documents/ApodiniIoTDeploymentProvider/config.json")
        )
        provider.registerAction(
            scope: .all,
            action:
                .docker(
                    DockerDiscoveryAction(
                        identifier: ActionIdentifier("docker_lifx"),
                        imageName: "hendesi/master-thesis:lifx-action",
                        fileUrl: URL(fileURLWithPath: deploymentOptions.deploymentDir)
                            .appendingPathComponent("lifx_devices"),
                        options: [
                            .privileged,
                            .volume(hostDir: deploymentOptions.deploymentDir, containerDir: "/app/tmp"),
                            .network("host"),
                            .command("/app/tmp --number-only"),
                            .credentials(username: "dummyUsername", password: "dummyPassword")
                        ]
                    )
                ),
            option: DeploymentDeviceMetadata(.lifx)
        )
        
        try provider.run()
        //        provider.registerAction(scope: .all, action: .action(LIFXDeviceDiscoveryAction.self), option: DeploymentDeviceMetadata(.lifx))
    }
}
