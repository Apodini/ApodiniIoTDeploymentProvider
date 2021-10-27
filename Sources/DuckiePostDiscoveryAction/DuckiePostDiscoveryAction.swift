//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//

import Foundation
import DeviceDiscovery
import NIO

public struct DuckiePostDiscoveryAction: PostDiscoveryAction {
    public static var identifier: ActionIdentifier {
        ActionIdentifier("duckie-post-discovery")
    }
    
    public func run(_ device: Device, on eventLoopGroup: EventLoopGroup, client: SSHClient?) throws -> EventLoopFuture<Int> {
        let eventLoop = eventLoopGroup.next()
        
        guard let client = client else {
            return eventLoop.makeSucceededFuture(0)
        }
        try client.bootstrap()
        
        if try client.executeAsBool(cmd: "cd /duckie-util", responseHandler: nil) {
            return eventLoop.makeSucceededFuture(1)
        } else {
            return eventLoop.makeSucceededFuture(0)
        }
    }
    
    public init() {}
}
