//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//

import Apodini
import ApodiniDeployRuntimeSupport
import ApodiniUtils
import ArgumentParser
import DeploymentTargetIoTCommon
import Foundation

public class IoTRuntime<Service: WebService>: DeploymentProviderRuntime {
    public static var identifier: DeploymentProviderID {
        iotDeploymentProviderId
    }
    
    public static var exportCommand: StructureExporter.Type {
        IoTStructureExporterCommand<Service>.self
    }
    
    public static var startupCommand: DeploymentStartupCommand.Type {
        IoTStartupCommand<Service>.self
    }
    
    public var deployedSystem: AnyDeployedSystem
    public var currentNodeId: DeployedSystemNode.ID
    
    private let currentNodeCustomLaunchInfo: IoTLaunchInfo
    
    public required init(deployedSystem: AnyDeployedSystem, currentNodeId: DeployedSystemNode.ID) throws {
        self.deployedSystem = deployedSystem
        self.currentNodeId = currentNodeId
        guard
            let node = deployedSystem.node(withId: currentNodeId),
            let launchInfo = node.readUserInfo(as: IoTLaunchInfo.self)
        else {
            throw ApodiniDeployRuntimeSupportError(
                deploymentProviderId: Self.identifier,
                message: "Unable to read userInfo"
            )
        }
        self.currentNodeCustomLaunchInfo = launchInfo
    }
    
    public func configure(_ app: Application) throws {
        let config = HTTPConfiguration(
            bindAddress: .interface(currentNodeCustomLaunchInfo.host.path,port: currentNodeCustomLaunchInfo.port)
        )
        config.configure(app)
    }
    
    public func handleRemoteHandlerInvocation<H: IdentifiableHandler>(
        _ invocation: HandlerInvocation<H>
    ) throws -> RemoteHandlerInvocationRequestResponse<H.Response.Content> {
        guard
            let LLI = invocation.targetNode.readUserInfo(as: IoTLaunchInfo.self),
            let url = URL(string: "\(LLI.host):\(LLI.port)")
        else {
            throw ApodiniDeployRuntimeSupportError(
                deploymentProviderId: identifier,
                message: "Unable to read port and construct url"
            )
        }
        return .invokeDefault(url: url)
    }
}

extension DeploymentDevice {
    /// A default deployment device meta data option. This can be used for handlers that are not particular for one device,
    /// but should be exported regardless of the found devices.
    public static var `default`: Self {
        DeploymentDevice(rawValue: "default")
    }
}
