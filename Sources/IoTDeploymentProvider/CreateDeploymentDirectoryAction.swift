//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//

import ApodiniUtils
import DeviceDiscovery
import Foundation
import Logging
import NIO

/// A simple `PostDiscoveryAction` to create the deployment directory on the raspberry pi
struct CreateDeploymentDirectoryAction: PostDiscoveryAction {
    static var identifier = ActionIdentifier(rawValue: "createDeploymentDir")
    
    @Configuration(IoTContext.deploymentDirectory)
    var deploymentDir: URL

    func run(_ device: Device, on eventLoopGroup: EventLoopGroup, client: SSHClient?) throws -> EventLoopFuture<Int> {
        try client?.bootstrap()
        try client?.fileManager.createDir(on: deploymentDir, permissions: 777, force: false)
        return eventLoopGroup.next().makeSucceededFuture(0)
    }
}
