//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//

import Apodini
import ApodiniDeployBuildSupport
import DeploymentTargetIoTCommon
import Foundation

extension DeploymentDevice {
    /// The custom `DeploymentDevice` option for the `DeploymentDeviceMetadata`. This can be used to annotate handlers.
    /// The user can associate this option with a `PostDiscoveryAction` by call `register` of the IoTDeploymentProvider.
    /// This tells the provider to enable all annotated handlers when deploying the web service **if** the associated action returned a positive value.
    public static var duckie: Self {
        DeploymentDevice(rawValue: "duckie")
    }
}
