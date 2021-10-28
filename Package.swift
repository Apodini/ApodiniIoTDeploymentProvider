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
            name: "DeploymentTargetIoT",
            targets: ["DeploymentTargetIoT"]
        ),
        .library(
            name: "DeploymentTargetIoTRuntime",
            targets: ["DeploymentTargetIoTRuntime"]
        ),
        .library(
            name: "DeploymentTargetIoTCommon",
            targets: ["DeploymentTargetIoTCommon"]
        ),
        .library(
            name: "LifxIoTDeploymentOption",
            targets: ["LifxIoTDeploymentOption"]
        ),
        .library(
            name: "DuckieIoTDeploymentOption",
            targets: ["DuckieIoTDeploymentOption"]
        ),
        .executable(
            name: "LifxDuckieIoTDeploymentTarget",
            targets: ["LifxDuckieIoTDeploymentTarget"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Apodini/Apodini.git", .upToNextMinor(from: "0.5.0")),
        .package(name: "swift-device-discovery", url: "https://github.com/Apodini/SwiftDeviceDiscovery.git", .branch("master")),
        .package(name: "swift-nio-lifx-impl", url: "https://github.com/Apodini/Swift-NIO-LIFX-Impl", .branch("develop")),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "0.4.0"))
    ],
    targets: [
        .target(
            name: "DeploymentTargetIoT",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftDeviceDiscovery", package: "swift-device-discovery"),
                .target(name: "DeploymentTargetIoTCommon"),
                .product(name: "ApodiniDeployBuildSupport", package: "Apodini"),
                .product(name: "ApodiniUtils", package: "Apodini")
            ]
        ),
        .target(
            name: "DeploymentTargetIoTRuntime",
            dependencies: [
                .product(name: "ApodiniDeployRuntimeSupport", package: "Apodini"),
                .target(name: "DeploymentTargetIoTCommon")
            ]
        ),
        .target(
            name: "DeploymentTargetIoTCommon",
            dependencies: [
                .product(name: "ApodiniDeployBuildSupport", package: "Apodini")
            ]
        ),
        .executableTarget(
            name: "LifxDuckieIoTDeploymentTarget",
            dependencies: [
                .target(name: "DeploymentTargetIoT"),
                .target(name: "LifxIoTDeploymentOption"),
                .target(name: "DeploymentTargetIoTCommon"),
                .target(name: "DuckieIoTDeploymentOption"),
                .target(name: "DuckiePostDiscoveryAction"),
                .product(name: "LifxDiscoveryActions", package: "swift-nio-lifx-impl")
            ]
        ),
        .target(
            name: "LifxIoTDeploymentOption",
            dependencies: [
                .product(name: "ApodiniDeployBuildSupport", package: "Apodini"),
                .target(name: "DeploymentTargetIoTCommon")
            ]
        ),
        .target(
            name: "DuckieIoTDeploymentOption",
            dependencies: [
                .product(name: "ApodiniDeployBuildSupport", package: "Apodini"),
                .target(name: "DeploymentTargetIoTCommon")
            ]
        ),
        .target(
            name: "DuckiePostDiscoveryAction",
            dependencies: [
                .product(name: "SwiftDeviceDiscovery", package: "swift-device-discovery")
            ]
        ),
        .testTarget(
            name: "IoTDeploymentTests",
            dependencies: [
                .target(name: "DeploymentTargetIoT")
            ]
        )
    ]
)
