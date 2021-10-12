//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//

import Foundation

struct CredentialStorage: Codable {
    typealias Mapping = [String: Credentials]
    
    static var dockerComposeKey: String = "docker-compose"
    
    private var storage: [Mapping]
    
    var readFromFile: Bool
    
    init(from file: URL?) {
        guard let file = file else {
            self.storage = []
            self.readFromFile = false
            return
        }
        
        do {
            let data = try Data(contentsOf: file)
            self.storage = try JSONDecoder().decode([Mapping].self, from: data)
            self.readFromFile = true
        } catch {
            fatalError("Failed to read configuration file. Error: \(error)")
        }
    }
    
    subscript(key: String) -> Credentials {
        get {
            let mappings = storage.filter { mappings in
                mappings.keys.contains(key)
            }
            
            precondition(!mappings.isEmpty, "No entry was found for key '\(key)'. Please check your config file.")
            precondition(mappings.count == 1, "The config file should only contain unique entries.")
            
            // we can force unwrap here, because of the precondition
            return mappings.first![key]! // swiftlint:disable:this force_unwrapping
        }
        set {
            storage.append([key: newValue])
        }
    }
}

struct Credentials: Codable {
    static let emptyCredentials = Credentials(username: "", password: "")
    
    let username: String
    let password: String
}
