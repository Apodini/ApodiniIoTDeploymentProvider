//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//       

import Foundation
import DeviceDiscovery
import ApodiniUtils
import Logging

public enum IoTContext {
    public static let deploymentDirectory = ConfigurationProperty("key_deployDir")

    static let defaultCredentials = Credentials(username: "ubuntu", password: "test1234")
    
    static var logger = Logger(label: "de.apodini.IoTDeployment")
    
    static let dockerVolumeTmpDir = URL(fileURLWithPath: "/app/tmp")
    
    private static var startDate = Date()
    
    static func copyResources(_ device: Device, origin: String, destination: String) throws {
        let task = Task(
            executableUrl: Self._findExecutable("rsync"),
            arguments: [
                "-avz",
                "-e",
                "'ssh'",
                origin,
                destination
            ],
            workingDirectory: nil,
            launchInCurrentProcessGroup: true
        )
        try task.launchSyncAndAssertSuccess()
    }
    
    static func rsyncHostname(_ device: Device, path: String) -> String {
        // swiftlint:disable:next force_unwrapping
        "\(device.username)@\(device.ipv4Address!):\(path)"
    }
    
    static func ipAddress(for device: Device) throws -> String {
        guard let ipaddress = device.ipv4Address else {
            throw IoTDeploymentError(description: "Unable to get ipaddress for \(device)")
        }
        return ipaddress
    }
    
    private static func _findExecutable(_ name: String) -> URL {
        guard let url = Task.findExecutable(named: name) else {
            fatalError("Unable to find executable '\(name)'")
        }
        return url
    }
    
    private static func getSSHClient(for device: Device) throws -> SSHClient {
        guard let ipAddress = device.ipv4Address else {
            throw IoTDeploymentError(description: "Failed to get sshclient for \(device)")
        }
        return try SSHClient(username: device.username, password: device.password, ipAdress: ipAddress)
    }
    
    /// A wrapper function that navigates to the specified working directory and executes the command remotely
    static func runTaskOnRemote(
        _ command: String,
        workingDir: String = "",
        device: Device,
        assertSuccess: Bool = true,
        responseHandler: ((String) -> Void)? = nil
    ) throws {
        let client = try getSSHClient(for: device)
        let cmd = workingDir.isEmpty ? command : "cd \(workingDir) && \(command)"
        if assertSuccess {
            client.executeWithAssertion(cmd: cmd, responseHandler: responseHandler)
        } else {
            _ = try client.executeAsBool(cmd: cmd, responseHandler: responseHandler)
        }
    }
    
    static func startTimer() {
        startDate = Date()
    }
    
    static func endTimer() {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: startDate, to: Date())
        guard
            let hours = components.hour,
            let minutes = components.minute,
            let seconds = components.second else {
                Self.logger.error("Unable to read timer")
                return
            }
        let hourString = hours < 10 ? "0\(hours)" : "\(hours)"
        let minuteString = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        let secondsString = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        logger.notice("Complete deployment in \(hourString):\(minuteString):\(secondsString)")
    }
    
    static func readUsernameAndPassword(for reason: String) -> Credentials {
        Self.logger.info("The username for \(reason) :")
        var username = readLine()
        while username.isEmpty {
            username = readLine()
        }
        Self.logger.info("The password for \(reason) :")
        let passw = getpass("")
        // swiftlint:disable:next force_unwrapping
        return Credentials(username: username!, password: String(cString: passw!))
    }
    
    static func runInDocker(
        imageName: String,
        command: String,
        device: Device,
        workingDir: URL,
        containerName: String = "",
        detached: Bool = false,
        privileged: Bool = false,
        volumeDir: URL = dockerVolumeTmpDir,
        port: Int = -1
    ) throws {
        var arguments: String {
            let args = [
                "sudo",
                "docker",
                "run",
                "--rm",
                containerName.isEmpty ? "" : "--name \(containerName)",
                port == -1 ? "" : "-p \(port):\(port)",
                detached ? "-d" : "",
                privileged ? "--privileged": "",
                "-v",
                "\(workingDir.path):\(volumeDir.path):Z",
                imageName,
                command
            ]
            return args.joined(separator: " ")
        }
        print(arguments)
        try runTaskOnRemote(arguments, workingDir: workingDir.path, device: device)
    }
    
    static func runInDockerCompose(configFileUrl: URL, envFileUrl: URL, device: Device, detached: Bool = false) throws {
        let hasDockerComposev2: Bool = try {
            let client = try getSSHClient(for: device)
            return try client.executeAsBool(cmd: "docker compose", responseHandler: nil)
        }()
        
        let arguments: String = {
            [
                "sudo",
                hasDockerComposev2 ? "docker compose" : "docker-compose",
                "-f",
                configFileUrl.path,
                "--env-file",
                envFileUrl.path,
                "up",
                detached ? "-d" : ""
            ].joined(separator: " ")
        }()
        print(arguments)
        try runTaskOnRemote(arguments, device: device)
    }
}

struct IoTDeploymentError: Swift.Error {
    let description: String
}

extension Dictionary {
    static func + (lhs: [Key: Value], rhs: [Key: Value]) -> [Key: Value] {
        lhs.merging(rhs) { $1 }
    }
}

extension Logger {
    static var iotLoggerLabel = "de.apodini.IoTDeployment"
    
    static func initializeLogger(dumpLog: Bool) throws -> Self {
        let fileManager = FileManager.default
        let logDir = FileManager.projectDirectory.appendingPathComponent("Logs")
        
        let fileTimestamp: String = {
            var buffer = [Int8](repeating: 0, count: 255)
            var timestamp = time(nil)
            let localTime = localtime(&timestamp)
            strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M", localTime)
            return buffer.withUnsafeBufferPointer {
                $0.withMemoryRebound(to: CChar.self) {
                    String(cString: $0.baseAddress!) // swiftlint:disable:this force_unwrapping
                }
            }
        }()
        
        if dumpLog {
            // create Logs dir if non-existent
            if !fileManager.fileExists(atPath: logDir.path) {
                try fileManager.createDirectory(at: logDir, withIntermediateDirectories: false)
            }
            return Logger(label: iotLoggerLabel, factory: { _ in
                IoTLogHandler(fileURL: logDir, label: iotLoggerLabel, fileTimeStamp: fileTimestamp)
            })
        }
        return Logger(label: iotLoggerLabel)
    }
}

extension FileManager {
    static var projectDirectory: URL {
        var fileUrl = URL(fileURLWithPath: #filePath)
        let decisivePathComponent = fileUrl.pathComponents.contains(".build") ? ".build" : "Sources"

        while fileUrl.lastPathComponent != decisivePathComponent {
            fileUrl.deleteLastPathComponent()
        }
        return fileUrl.deletingLastPathComponent()
    }
}

struct IoTLogHandler: LogHandler {
    let fileURL: URL
    let label: String
    let fileTimeStamp: String
    
    var metadata: Logger.Metadata = [:]
    
    var logLevel: Logger.Level = .debug
    
    // swiftlint:disable:next function_parameter_count
    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        let dumpfileURL = fileURL.appendingPathComponent(
            "\(fileTimeStamp)_\(Bundle.main.executableURL?.lastPathComponent ?? "")_dump.log"
        )
        
        let str = "\(self.timestamp()) \(level) \(self.label): \(message)"
        print(str)
        
        guard let data = (str + "\n").data(using: .utf8) else {
            printErrorMsg()
            return
        }
        if let fileHandle = FileHandle(forWritingAtPath: dumpfileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
        } else {
            do {
                try data.write(to: dumpfileURL, options: .atomic)
            } catch {
                printErrorMsg(error: error)
            }
        }
    }
    
    private func printErrorMsg(error: Error? = nil) {
        print("\(self.timestamp()) \(Logger.Level.error) \(self.label): \(error). Failed to log data to file.")
    }
    
    private func timestamp() -> String {
        var buffer = [Int8](repeating: 0, count: 255)
        var timestamp = time(nil)
        let localTime = localtime(&timestamp)
        strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", localTime)
        return buffer.withUnsafeBufferPointer {
            $0.withMemoryRebound(to: CChar.self) {
                String(cString: $0.baseAddress!) // swiftlint:disable:this force_unwrapping
            }
        }
    }
    
    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            metadata[metadataKey]
        }
        set(newValue) {
            metadata[metadataKey] = newValue
        }
    }
}
