// swift-tools-version:5.5

//
// This source file is part of the Apodini Template open source project
//
// SPDX-FileCopyrightText: 2021 Paul Schmiedmayer and the project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//

import PackageDescription


let package = Package(
    name: "ApodiniIoTDeploymentProvider",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "IoTDeploymentProvider",
            targets: ["IoTDeploymentProvider"]
        ),
        .library(
            name: "IoTDeploymentProviderRuntime",
            targets: ["IoTDeploymentProviderRuntime"]
        ),
        .library(
            name: "IoTDeploymentProviderCommon",
            targets: ["IoTDeploymentProviderCommon"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Apodini/Apodini.git", .branch("develop")),
        .package(name: "swift-device-discovery", url: "https://github.com/Apodini/SwiftDeviceDiscovery.git", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "0.4.0"))
    ],
    targets: [
        .target(
            name: "IoTDeploymentProvider",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftDeviceDiscovery", package: "swift-device-discovery"),
                .target(name: "IoTDeploymentProviderCommon"),
                .product(name: "ApodiniDeployerBuildSupport", package: "Apodini"),
                .product(name: "ApodiniUtils", package: "Apodini")
            ]
        ),
        .target(
            name: "IoTDeploymentProviderRuntime",
            dependencies: [
                .product(name: "ApodiniDeployerRuntimeSupport", package: "Apodini"),
                .target(name: "IoTDeploymentProviderCommon")
            ]
        ),
        .target(
            name: "IoTDeploymentProviderCommon",
            dependencies: [
                .product(name: "ApodiniDeployerBuildSupport", package: "Apodini")
            ]
        ),
        .testTarget(
            name: "IoTDeploymentProviderTests",
            dependencies: [
                .target(name: "IoTDeploymentProvider")
            ]
        )
    ]
)
