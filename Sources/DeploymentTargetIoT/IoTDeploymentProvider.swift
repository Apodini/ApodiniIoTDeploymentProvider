//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ApodiniDeployBuildSupport
import ArgumentParser
import DeviceDiscovery
import Apodini
import ApodiniUtils
import Logging
import DeploymentTargetIoTCommon


/// A deployment provider that handles the automatic deployment of a given web service to IoT devices in the network.
public class IoTDeploymentProvider: DeploymentProvider { // swiftlint:disable:this type_body_length
    /// Used to define the scope in which a `PostDiscoveryAction` is registered to the provider
    public enum RegistrationScope {
        /// The action is registered to all device types
        case all
        /// The action is registered to some device types
        case some([String])
        /// The action is registered to just one device type
        case one(String)
    }
    
    /// Defines the input of the deployment
    public enum InputType {
        /// Use a docker image of the web service for deployment
        case dockerImage(String)
        /// Use the swift package for deployment
        case package
        /// Use a docker compose file for deployment
        /// - Parameter : The URL to the compose file
        case dockerCompose(URL)
    }
    
    /// Defines the mode in which the web service is executed
    private enum Mode {
        case structureExport(String, URL, String, Int)
        case startup(URL, String, String)
    }
    
    /// The identifier of the deployment provider
    public static var identifier: DeploymentProviderID {
        iotDeploymentProviderId
    }
    
    public let inputType: InputType
    
    public let searchableTypes: [String]
    public let productName: String
    public let packageRootDir: URL
    public let deploymentDir: URL
    public let webServiceArguments: [String]
    
    public let automaticRedeployment: Bool
    public let port: Int
    
    // Remove later
    public let dryRun = false
    
    public var target: DeploymentProviderTarget {
        .spmTarget(packageUrl: packageRootDir, targetName: productName)
    }
    
    private var isRunning = false {
        didSet {
            isRunning ? IoTContext.startTimer() : IoTContext.endTimer()
        }
    }
    
    private var composeRemoteLocation: URL {
        deploymentDir.appendingPathComponent("docker-compose.yml")
    }
    
    private var postActionMapping: [DeviceIdentifier: [(DeploymentDeviceMetadata, DeviceDiscovery.PostActionType)]] = [:]
    private let additionalConfiguration: [ConfigurationProperty: Any]
    
    private var credentialStorage: CredentialStorage
    
    internal let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    
    internal var results: [DiscoveryResult] = []
    
    private var packageName: String {
        packageRootDir.lastPathComponent
    }
    
    private var remotePackageRootDir: URL {
        deploymentDir.appendingPathComponent(packageName)
    }
    
    private var flattenedWebServiceArguments: String {
        webServiceArguments.joined(separator: " ")
    }
    
    /// Initializes a new `IotDeploymentProvider`
    /// - Parameter searchableTypes: An Array of devices types or their pushlished services that the provider will look for.
    /// - Parameter productName: The name of the web service's SPM target/product
    /// - Parameter packageRootDir: The directory containing the Package.swift with the to-be-deployed web service's target
    /// - Parameter deploymentDir: The remote directory the web service will be deployed/copied to
    /// - Parameter automaticRedeployment: If set, the deployment provider listens for changes in the the working directory and automatically redeploys changes to the affected nodes.
    /// - Parameter additionalConfiguration: Manually add user-defined `ConfigurationStorage` that will be accessible by the `PostDiscoveryAction`s. Defaults to [:]
    /// - Parameter webServiceArguments: If your web service has its own arguments/options, pass them here, otherwise the deployment might fail. Defaults to [].
    /// - Parameter input: Specify if the deployment is done via docker or swift package.
    /// - Parameter port: The port the deployed web service will listen on. Defaults to 8080
    public init(
        searchableTypes: [String],
        productName: String,
        packageRootDir: String,
        deploymentDir: String = "/usr/deployment",
        automaticRedeployment: Bool,
        additionalConfiguration: [ConfigurationProperty: Any] = [:],
        webServiceArguments: [String] = [],
        input: InputType,
        port: Int = 8080,
        configurationFile: URL? = nil
    ) {
        self.searchableTypes = searchableTypes
        self.productName = productName
        self.packageRootDir = URL(fileURLWithPath: packageRootDir)
        // swiftlint:disable:next force_unwrapping
        self.deploymentDir = URL(string: deploymentDir)!
        self.automaticRedeployment = automaticRedeployment
        self.additionalConfiguration = additionalConfiguration
        self.webServiceArguments = webServiceArguments
        self.inputType = input
        self.port = port
        
        self.credentialStorage = CredentialStorage(from: configurationFile)
        
        // initialize empty arrays
        searchableTypes.forEach {
            postActionMapping[DeviceIdentifier($0)] = []
        }
    }
    
    /// Runs the deployment
    public func run() throws {
        IoTContext.logger.notice("Starting deployment of \(productName)..")
        isRunning = true

        readCredentialsIfNeeded()
        
        IoTContext.logger.info("Searching for devices in the network")
        for type in searchableTypes {
            let discovery = try setup(for: type)
            
            results = try discovery.run(2).wait()
            IoTContext.logger.info("Found: \(results)")
            
            try results.forEach {
                try deploy($0, discovery: discovery)
            }
            IoTContext.logger.notice("Completed deployment for all devices of type \(type)")
            discovery.stop()
        }
        try listenForChanges()
        isRunning = false
    }
    
    /// Register a `PostDiscoveryAction` with a `DeploymentDeviceMetadata` to the deployment provider.
    /// - Parameter scope: The `RegistrationScope` of the action.
    /// - Parameter action: The `PostDiscoveryAction`
    /// - Parameter option: The corresponding option that will be associated with the action
    public func registerAction(
        scope: RegistrationScope,
        action: DeviceDiscovery.PostActionType,
        option: DeploymentDeviceMetadata
    ) {
        switch scope {
        case .all:
            self.searchableTypes.forEach { postActionMapping[DeviceIdentifier($0)]?.append((option, action)) }
        case .some(let array):
            array.forEach { postActionMapping[DeviceIdentifier($0)]?.append((option, action)) }
        case .one(let type):
            postActionMapping[DeviceIdentifier(type)]?.append((option, action))
        }
    }
    
    internal func deploy(_ result: DiscoveryResult, discovery: DeviceDiscovery) throws {
        IoTContext.logger.debug("Cleaning up any leftover actions data in deployment directory")
        try cleanup(on: result.device)
        
        guard
            // do nothing if there were no post actions
            !result.foundEndDevices.isEmpty,
            // do nothing if all post actions returned 0
            result.foundEndDevices.values.contains(where: { $0 != 0 })
        else {
            IoTContext.logger.warning("No end devices were found for device \(String(describing: result.device.hostname))")
            return
        }
        
        IoTContext.logger.info("Starting deployment to device \(String(describing: result.device.hostname))")
        
        let device = result.device
        
        try performInputRelatedActions(result)
        
        IoTContext.logger.info("Retrieving the system structure")
        let (modelFileUrl, deployedSystem) = try retrieveDeployedSystem(result: result)
        IoTContext.logger.notice("System structure written to '\(modelFileUrl)'")
        
        // Check if we have a suitable deployment node.
        // If theres none for this device, there's no point to continue
        guard let deploymentNode = try self.deploymentNode(for: result, deployedSystem: deployedSystem)
        else {
            IoTContext.logger.warning("Couldn't find a deployment node for \(String(describing: result.device.hostname))")
            return
        }
        
        // Run web service on deployed node
        IoTContext.logger.info("Starting web service on remote node!")
        try run(on: deploymentNode, device: device, modelFileUrl: modelFileUrl)
        
        IoTContext.logger.notice("Finished deployment for \(String(describing: result.device.hostname)) containing \(deploymentNode.id)")
    }
    
    internal func retrieveDeployedSystem(result: DiscoveryResult) throws -> (URL, DeployedSystem) {
        switch inputType {
        case .package:
            return try retrieveDeployedSystemUsingPackage(result: result)
        default:
            return try retrieveDeployedSystemUsingDocker(type: inputType, result: result)
        }
    }
    
    internal func performInputRelatedActions(_ result: DiscoveryResult) throws {
        func loginIntoDocker(credentialKey: String) throws {
            let dockerCredentials = credentialStorage[credentialKey]
            
            IoTContext.logger.info("Logging into docker")
            try IoTContext.runTaskOnRemote("sudo docker login -u \(dockerCredentials.username) -p \(dockerCredentials.password)", workingDir: self.remotePackageRootDir.path, device: result.device, assertSuccess: false)
        }
        
        
        switch inputType {
        case .package:
            IoTContext.logger.info("Copying sources to remote")
            try copyResourcesToRemote(result)
            
            IoTContext.logger.info("Fetching the newest dependencies")
            try fetchDependencies(on: result.device)
            
            IoTContext.logger.info("Building package on remote")
            try buildPackage(on: result.device)
        case .dockerCompose(let fileUrl):
            try loginIntoDocker(credentialKey: CredentialStorage.dockerComposeKey)
            
            IoTContext.logger.info("Copying docker-compose to remote")
            try IoTContext.copyResources(
                result.device,
                origin: fileUrl.path,
                destination: IoTContext.rsyncHostname(result.device, path: self.deploymentDir.path)
            )
        case .dockerImage(let imageName):
            IoTContext.logger.info("A docker image was specified, so skipping copying, fetching and building..")
            try loginIntoDocker(credentialKey: imageName)
        }
    }
    
    internal func setup(for type: String) throws -> DeviceDiscovery {
        let discovery = DeviceDiscovery(DeviceIdentifier(type), domain: .local)
        var actions: [DeviceDiscovery.PostActionType] = [
            .action(CreateDeploymentDirectoryAction.self)
        ]
        
        if let mapping = postActionMapping.first(where: { $0.key.rawValue == type }) {
            actions.append(contentsOf: mapping.value.compactMap { $0.1 })
        }
        
        discovery.registerActions(
            actions
        )

        let credentials = credentialStorage[type]
        let config: [ConfigurationProperty: Any] = [
            .username: credentials.username,
            .password: credentials.password,
            .runPostActions: true,
            IoTContext.deploymentDirectory: self.deploymentDir
        ] + additionalConfiguration
        discovery.configuration = .init(from: config)
        
        return discovery
    }
    
    internal func run(on node: DeployedSystemNode, device: Device, modelFileUrl: URL) throws {
        let handlerIds: String = node.exportedEndpoints.compactMap { $0.handlerId.rawValue }.joined(separator: ",")
        let buildUrl = remotePackageRootDir
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
        let tmuxName = productName
        IoTContext.logger.debug("tmux new-session -d -s \(tmuxName) './\(productName) \(flattenedWebServiceArguments) deploy startup iot \(modelFileUrl.path) --node-id \(node.id) --endpoint-ids \(handlerIds)'")
        switch inputType {
        case .package:
            try IoTContext.runTaskOnRemote(
                "tmux new-session -d -s \(tmuxName) './\(productName) \(flattenedWebServiceArguments) deploy startup iot \(modelFileUrl.path) --node-id \(node.id) --endpoint-ids \(handlerIds)'",
                workingDir: buildUrl.path,
                device: device
            )
        case .dockerImage(let imageName):
            let volumeURL = IoTContext.dockerVolumeTmpDir.appendingPathComponent("WebServiceStructure.json")
            try IoTContext.runInDocker(
                imageName: imageName,
                command: "\(flattenedWebServiceArguments) deploy startup iot \(volumeURL.path) --node-id \(node.id) --endpoint-ids \(handlerIds)",
                device: device,
                workingDir: deploymentDir,
                containerName: productName,
                detached: true,
                privileged: true,
                port: port
            )
        case .dockerCompose(_):
            let volumeURL = IoTContext.dockerVolumeTmpDir.appendingPathComponent("WebServiceStructure.json")
            let envFileUrl = try createEnvFile(for: .startup(volumeURL, node.id, handlerIds), device: device)
            
            try IoTContext.runInDockerCompose(
                configFileUrl: composeRemoteLocation,
                envFileUrl: envFileUrl,
                device: device,
                detached: true
            )
        }
    }
    
    internal func deploymentNode(for result: DiscoveryResult, deployedSystem: DeployedSystem) throws -> DeployedSystemNode? {
        let ipAddress = try IoTContext.ipAddress(for: result.device)
        let nodes = deployedSystem.nodes.filter { $0.id == ipAddress }
        // Since the node's id is the ip address, there should only be one deploymentnode per device.
        assert(nodes.count == 1, "There should only be one deployment node per end device")
        
        return nodes.first
    }
    
    // MARK: - Retrieve Deployed System
    private func retrieveDeployedSystemUsingDocker(type: InputType, result: DiscoveryResult) throws -> (URL, DeployedSystem) {
        // ensure remote host dir is writable
        try IoTContext.runTaskOnRemote("sudo chmod 777 \(packageName)", workingDir: deploymentDir.path, device: result.device, assertSuccess: false)
        let filename = "WebServiceStructure.json"
        let fileUrl = IoTContext.dockerVolumeTmpDir.appendingPathComponent(filename)

        let actionKeys = postActionMapping
            .first(where: { $0.key == result.device.identifier })?
            .value
            .filterPositiveResults(result: result)
            .compactMap { $0.0.getOptionRawValue() }
            .joined(separator: ",")
            .appending(",")
            .appending("default")
        let ipAddress = try IoTContext.ipAddress(for: result.device)
        
        switch type {
        case .dockerImage(let imageName):
            try IoTContext.runInDocker(
                imageName: imageName,
                command: "\(flattenedWebServiceArguments) deploy export-ws-structure iot \(fileUrl.path) --ip-address \(ipAddress) --action-keys \(actionKeys ?? "default") --port \(port) --docker",
                device: result.device,
                workingDir: deploymentDir
            )
        case .dockerCompose(_):
            let envFileUrl = try createEnvFile(for: .structureExport(actionKeys ?? "default", fileUrl, ipAddress, port), device: result.device)
            try IoTContext.runInDockerCompose(configFileUrl: composeRemoteLocation, envFileUrl: envFileUrl, device: result.device)
        default:
            // should not happen
            break
        }

        let hostFilePath = deploymentDir.appendingPathComponent(filename)
        
        var responseString = ""
        try IoTContext.runTaskOnRemote(
            "cat \(hostFilePath)",
            workingDir: self.deploymentDir.path,
            device: result.device,
            responseHandler: { response in
                responseString = response
            }
        )
        // swiftlint:disable:next force_unwrapping
        let responseData = responseString.data(using: .utf8)!
        let deployedSystem = try JSONDecoder().decode(DeployedSystem.self, from: responseData)
        
        return (hostFilePath, deployedSystem)
    }
    
    // Since we dont want to compile the package locally just to retrieve the structure, we retrieve the structure remotely on every device the service is deployed on. On the devices, we compile the package anyway, so just use this.
    // We could do it just once and copy the file around, but for now this should be fine
    private func retrieveDeployedSystemUsingPackage(result: DiscoveryResult) throws -> (URL, DeployedSystem) {
        let modelFileName = "AM_\(UUID().uuidString).json"
        let remoteFilePath = deploymentDir.appendingPathComponent(modelFileName, isDirectory: false)
        let device = result.device
        
        let buildUrl = remotePackageRootDir
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
        
        let actionKeys = postActionMapping
            .first(where: { $0.key == result.device.identifier })?
            .value
            .compactMap { $0.0.getOptionRawValue() }
            .joined(separator: ",")
            .appending(",")
            .appending("default")
        
        let ipAddress = try IoTContext.ipAddress(for: device)
        try IoTContext.runTaskOnRemote(
            "./\(productName) \(flattenedWebServiceArguments) deploy export-ws-structure iot \(remoteFilePath) --ip-address \(ipAddress) --action-keys \(actionKeys ?? "default") --port \(port)",
            workingDir: buildUrl.path,
            device: device
        )
        // Since we are on remote, we need to decode the file differently.
        // Check if there are better solutions
        var responseString = ""
        try IoTContext.runTaskOnRemote(
            "cat \(remoteFilePath)",
            workingDir: self.deploymentDir.path,
            device: device,
            responseHandler: { response in
                responseString = response
            }
        )
        // swiftlint:disable:next force_unwrapping
        let responseData = responseString.data(using: .utf8)!
        let deployedSystem = try JSONDecoder().decode(DeployedSystem.self, from: responseData)
        
        return (remoteFilePath, deployedSystem)
    }
    
// MARK: - Docker compose related methods
    private func createEnvFile(for mode: Mode, device: Device) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("deployment.env")
        let envString: String = {
            switch mode {
            case let .structureExport(keys, fileURL, ipAddress, port):
                let command = "\(flattenedWebServiceArguments) deploy export-ws-structure iot \(fileURL.path) --ip-address \(ipAddress) --action-keys \(keys) --port \(port) --docker"
                return
                    """
                        ENV_FILEPATH=\(fileURL.path)
                        ENV_COMMAND=\(command)
                        ENV_DEPLOYPATH=\(deploymentDir.path)
                    """
            case let .startup(fileURL, nodeId, handlerIds):
                let command = "\(flattenedWebServiceArguments) deploy startup iot \(fileURL.path) --node-id \(nodeId) --endpoint-ids \(handlerIds)"
                return
                    """
                        ENV_FILEPATH=\(fileURL.path)
                        ENV_COMMAND=\(command)
                        ENV_DEPLOYPATH=\(deploymentDir.path)
                    """
            }
        }()
    
        let data = Data(envString.utf8)

        try data.write(to: url)
        IoTContext.logger.info("Created env file at \(url.path)")
        
        try IoTContext.copyResources(device, origin: url.path, destination: IoTContext.rsyncHostname(device, path: self.deploymentDir.path))
        IoTContext.logger.info("Copied it to remote")
        
        return self.deploymentDir.appendingPathComponent("deployment.env")
    }
    
// MARK: - Miscellaneous
    private func copyResourcesToRemote(_ result: DiscoveryResult) throws {
        // we dont need any existing build files because we are moving to a different aarch
        let fileManager = FileManager.default
        if fileManager.directoryExists(atUrl: packageRootDir.appendingPathComponent(".build")) {
            try fileManager.removeItem(at: packageRootDir.appendingPathComponent(".build"))
        }
        try IoTContext.copyResources(
            result.device,
            origin: packageRootDir.path,
            destination: IoTContext.rsyncHostname(result.device, path: self.deploymentDir.path)
        )
    }
    
    private func fetchDependencies(on device: Device) throws {
        try IoTContext.runTaskOnRemote(
            "swift package update",
            workingDir: self.remotePackageRootDir.path,
            device: device
        )
    }
    
    private func buildPackage(on device: Device) throws {
        try IoTContext.runTaskOnRemote(
            "swift build -c debug --product \(self.productName)",
            workingDir: self.remotePackageRootDir.path,
            device: device
        )
    }
    
    private func cleanup(on device: Device) throws {
        try IoTContext.runTaskOnRemote(
            "sudo rm -rfv !(\"\(packageName)\")",
            workingDir: self.deploymentDir.path,
            device: device,
            assertSuccess: false
        )
    }
    
    private func readCredentialsIfNeeded() {
        guard !credentialStorage.readFromFile else {
            return
        }
        if case let .dockerImage(imageName) = inputType {
            IoTContext.logger.notice("A docker image '\(imageName)' has been specified as input. Please enter the credentials to access the docker repo. Skip this step by pressing enter if it's a public repo.")
            credentialStorage[imageName] = IoTContext.readUsernameAndPassword(for: "docker")
        } else if case let .dockerCompose(fileUrl) = inputType {
            IoTContext.logger.notice("A docker compose file at '\(fileUrl)' has been specified as input. Please enter the credentials to access the docker repo. Skip this step by pressing enter if it's a public repo.")
            credentialStorage[CredentialStorage.dockerComposeKey] = IoTContext.readUsernameAndPassword(for: CredentialStorage.dockerComposeKey)
        }
        
        searchableTypes.forEach { type in
            IoTContext.logger.notice("Please enter credentials for \(type)")
            credentialStorage[type] = dryRun ? IoTContext.defaultCredentials : IoTContext.readUsernameAndPassword(for: type)
        }
    }
}

private extension Array where Element == (DeploymentDeviceMetadata, DeviceDiscovery.PostActionType) {
    func filterPositiveResults(result: DiscoveryResult) -> [Element] {
        filter { element in
            guard let amount = result.foundEndDevices[element.1.identifier] else {
                return false
            }
            return amount > 0
        }
    }
}

extension DeploymentDeviceMetadata {
    func getOptionRawValue() -> String? {
        self.value.option(for: .deploymentDevice)?.rawValue
    }
} // swiftlint:disable:this file_length
