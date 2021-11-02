//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Apodini
import DeviceDiscovery

private enum EvaluationType {
    case newDevice
    case changedEndDevices
    case noEndDevices
    case noChange
}

extension IoTDeploymentProvider {
    func listenForChanges() throws {
        func checkForLeavingDevices(_ newResults: [DiscoveryResult]) throws {
            let leavingDevices = self.results.filter { oldResult in
                let ipAddress = oldResult.device.ipv4Address ?? ""
                return !newResults
                    .compactMap { $0.device.ipv4Address }
                    .contains(ipAddress)
            }
            guard !leavingDevices.isEmpty else {
                return
            }
            IoTContext.logger.info("Found \(leavingDevices.count) leaving devices. Trying shutdown the web service gracefully.")
            try leavingDevices.forEach {
                try killInstanceOnRemote($0.device)
            }
            IoTContext.logger.info("Shutdown the web service gracefully.")
        }
 
        guard automaticRedeployment else {
            IoTContext.logger.notice("'automaticRedeploy' was set to false. Exiting.")
            return
        }
        IoTContext.logger.notice("'automaticRedeploy' was set to true. Scanning network for changes..")
        
        let timer = Timer(fire: Date(), interval: redeploymentInterval, repeats: true, block: { _ in
            do {
                for type in self.searchableTypes {
                    let discovery = try self.setup(for: type)
                    
                    // Run discovery with 30 seconds timeout
                    let results = try discovery.run().wait()
                    
                    try checkForLeavingDevices(results)
                    for result in results {
                        // Evaluate if & which changes occurred
                        let evaluation = try self.evaluateChanges(result, discovery: discovery)
                        
                        switch evaluation {
                        case .newDevice:
                            try self.deploy(result, discovery: discovery)
                        case .changedEndDevices:
                            try self.restartingWebService(on: result, discovery: discovery)
                        case .noChange, .noEndDevices:
                            continue
                        }
                    }
                    
                    self.results = results
                    discovery.stop()
                }
            } catch {
                fatalError("An error occurred while performing the automatic redeployment: \(error)")
            }
        })
        
        RunLoop.current.add(timer, forMode: .common)
        // Look for changes until stopped
        RunLoop.current.run()
    }
    
    private func evaluateChanges(_ result: DiscoveryResult, discovery: DeviceDiscovery) throws -> EvaluationType {
        // swiftlint:disable:next force_unwrapping
        let isNewDevice = !self.results.compactMap { $0.device.ipv4Address }.contains(result.device.ipv4Address!)
        
        if isNewDevice {
            // Trigger normal deployment
            IoTContext.logger.info("Detected change: New Device!")
            return .newDevice
        }
        
        // It's not a new device, so there must be a counterpart in the existing results
        guard let oldResult = self.results.first(where: { $0.device.ipv4Address == result.device.ipv4Address }) else {
            // should not happen
            IoTContext.logger.info("No change detected")
            return .noChange
        }
        guard result.foundEndDevices != oldResult.foundEndDevices else {
            // nothing changed
            IoTContext.logger.info("No change detected")
            return .noChange
        }
        
        // check if we had end devices but now none
        if result.foundEndDevices.allSatisfy({ $0.value == 0 }) &&
            oldResult.foundEndDevices.contains(where: { $0.value > 0 }) {
            // if so, kill running instance and remove deployment
            IoTContext.logger.info("Detected change: Updated end devices! No end device could be found anymore")
            IoTContext.logger.info("Removing deployment directory and stopping process")
            try killInstanceOnRemote(result.device)
            //            try IoTContext.runTaskOnRemote("sudo rm -rdf \(deploymentDir.path)", device: result.device)
            return .noEndDevices
        }
        
        // check if the amount of found devices was 0 before -> this would need to copy and build first.
        if oldResult.foundEndDevices.allSatisfy({ $0.value == 0 }) &&
            result.foundEndDevices.contains(where: { $0.value > 0 }) {
            IoTContext.logger.info("Detected change: Updated end devices! First end device, previously none.")
            IoTContext.logger.info("Starting complete deployment process for device")
            return .newDevice
        }
        IoTContext.logger.info("Detected change: Changed end devices!")
        return .changedEndDevices
    }
    
    private func restartingWebService(on result: DiscoveryResult, discovery: DeviceDiscovery) throws {
        IoTContext.logger.info("Stopping running instance on remote")
        try killInstanceOnRemote(result.device)
        
        IoTContext.logger.info("Retrieve update structure")
        let (modelFileUrl, deployedSystem) = try retrieveDeployedSystem(result: result)
        
        // Check if we have a suitable deployment node.
        // If theres none for this device, there's no point to continue
        guard let deploymentNode = try self.deploymentNode(for: result, deployedSystem: deployedSystem)
        else {
            IoTContext.logger.warning("Couldn't find a deployment node for \(String(describing: result.device.hostname))")
            return
        }
        
        // Run web service on deployed node
        IoTContext.logger.info("Restarting web service on remote node!")
        try run(on: deploymentNode, device: result.device, modelFileUrl: modelFileUrl)
    }
    
    private func killInstanceOnRemote(_ device: Device) throws {
        switch inputType {
        case .package:
            try IoTContext.runTaskOnRemote("tmux kill-session -t \(productName)", device: device, assertSuccess: false)
        case .dockerImage(_), .dockerCompose(_):
            try IoTContext.runTaskOnRemote("docker stop $(docker ps -a -q); docker rm $(docker ps -a -q)", device: device, assertSuccess: false)
        }
    }
}
