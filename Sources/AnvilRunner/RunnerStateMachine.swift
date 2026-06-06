import Foundation

// MARK: - State Machine

/// Represents the current state of runner configuration on this machine.
public enum RunnerState: String, Sendable, CaseIterable {
    case freshClone       = "fresh-clone"
    case built            = "built"
    case configured       = "configured"
    case running          = "running"
    case stopped          = "stopped"
    
    public var description: String {
        switch self {
        case .freshClone:
            return "Repository cloned but not built"
        case .built:
            return "Binary built, no runners configured"
        case .configured:
            return "Runners configured but not started"
        case .running:
            return "Runners are active and processing jobs"
        case .stopped:
            return "Runners configured but stopped"
        }
    }
}

/// Detects the current state of runners by inspecting the filesystem and processes.
public struct RunnerStateDetector: Sendable {
    public static let shared = RunnerStateDetector()
    
    private let defaultInstallDir = ("~/actions-runner" as NSString).expandingTildeInPath
    
    private init() {}
    
    public func detect(installDirectory: String? = nil) async -> RunnerState {
        let installDir = installDirectory ?? defaultInstallDir
        
        // Check if binary is built
        let binaryBuilt = FileManager.default.fileExists(
            atPath: ProjectPaths.releaseBinary
        )
        
        if !binaryBuilt {
            return .freshClone
        }
        
        // Check if any runners are configured
        let runnersConfigured = await hasConfiguredRunners(in: installDir)
        
        if !runnersConfigured {
            return .built
        }
        
        // Check if runners are running
        let runnersRunning = await hasRunningRunners(in: installDir)
        
        if runnersRunning {
            return .running
        }
        
        return .stopped
    }
    
    private func hasConfiguredRunners(in directory: String) async -> Bool {
        guard FileManager.default.fileExists(atPath: directory) else { return false }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory)
            return contents.contains { item in
                FileManager.default.fileExists(atPath: "\(directory)/\(item)/run.sh")
            }
        } catch {
            return false
        }
    }
    
    private func hasRunningRunners(in directory: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "Runner.Listener"]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Action Discovery

/// An action that can be performed from a given runner state.
public struct RunnerAction: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let requiresConfirmation: Bool
    public let requiresToken: Bool
    public let parameters: [RunnerActionParameter]
    public let availableFromStates: [RunnerState]
    
    public init(
        id: String,
        name: String,
        description: String,
        requiresConfirmation: Bool = false,
        requiresToken: Bool = false,
        parameters: [RunnerActionParameter] = [],
        availableFromStates: [RunnerState]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.requiresConfirmation = requiresConfirmation
        self.requiresToken = requiresToken
        self.parameters = parameters
        self.availableFromStates = availableFromStates
    }
}

/// A parameter required by a runner action.
public struct RunnerActionParameter: Sendable {
    public let name: String
    public let type: ParameterType
    public let description: String
    public let required: Bool
    public let defaultValue: String?
    
    public enum ParameterType: String, Sendable {
        case string
        case boolean
        case integer
        case path
        case url
        case token
    }
    
    public init(
        name: String,
        type: ParameterType,
        description: String,
        required: Bool = true,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.defaultValue = defaultValue
    }
}

/// Discovers all available actions from the current runner state.
public struct RunnerActionDiscovery: Sendable {
    public static let shared = RunnerActionDiscovery()
    
    private let allActions: [RunnerAction] = [
        RunnerAction(
            id: "build",
            name: "Build anvil-runner",
            description: "Compile the release binary",
            availableFromStates: [.freshClone]
        ),
        RunnerAction(
            id: "doctor",
            name: "Run health checks",
            description: "Check host readiness for running GitHub Actions",
            availableFromStates: [.freshClone, .built, .configured, .running, .stopped]
        ),
        RunnerAction(
            id: "discover",
            name: "Discover capabilities",
            description: "Read-only scan of host tools, agents, network, and power",
            availableFromStates: [.freshClone, .built, .configured, .running, .stopped]
        ),
        RunnerAction(
            id: "setup",
            name: "Set up runners",
            description: "Download, configure, and register GitHub Actions runners for a repository",
            requiresConfirmation: true,
            requiresToken: true,
            parameters: [
                RunnerActionParameter(name: "repo", type: .url, description: "GitHub repository URL", required: true),
                RunnerActionParameter(name: "token", type: .token, description: "GitHub personal access token with repo scope", required: true),
                RunnerActionParameter(name: "count", type: .integer, description: "Number of runner instances", required: false, defaultValue: "2"),
                RunnerActionParameter(name: "name-prefix", type: .string, description: "Runner name prefix", required: false, defaultValue: "macmini"),
                RunnerActionParameter(name: "install-dir", type: .path, description: "Installation directory", required: false, defaultValue: "~/actions-runner"),
            ],
            availableFromStates: [.freshClone, .built, .stopped]
        ),
        RunnerAction(
            id: "start",
            name: "Start runners",
            description: "Launch configured runner instances",
            parameters: [
                RunnerActionParameter(name: "count", type: .integer, description: "Number of runners to start", required: false, defaultValue: "2"),
                RunnerActionParameter(name: "name-prefix", type: .string, description: "Runner name prefix", required: false, defaultValue: "macmini"),
            ],
            availableFromStates: [.configured, .stopped]
        ),
        RunnerAction(
            id: "stop",
            name: "Stop runners",
            description: "Gracefully stop running runner instances",
            requiresConfirmation: true,
            parameters: [
                RunnerActionParameter(name: "count", type: .integer, description: "Number of runners to stop", required: false, defaultValue: "2"),
                RunnerActionParameter(name: "name-prefix", type: .string, description: "Runner name prefix", required: false, defaultValue: "macmini"),
            ],
            availableFromStates: [.running]
        ),
        RunnerAction(
            id: "remove",
            name: "Remove runners",
            description: "Unregister runners from GitHub and delete local files",
            requiresConfirmation: true,
            requiresToken: true,
            parameters: [
                RunnerActionParameter(name: "count", type: .integer, description: "Number of runners to remove", required: false, defaultValue: "2"),
                RunnerActionParameter(name: "name-prefix", type: .string, description: "Runner name prefix", required: false, defaultValue: "macmini"),
                RunnerActionParameter(name: "token", type: .token, description: "GitHub runner removal token", required: true),
                RunnerActionParameter(name: "force-local", type: .boolean, description: "Delete local files without unregistering from GitHub", required: false, defaultValue: "false"),
            ],
            availableFromStates: [.configured, .running, .stopped]
        ),
        RunnerAction(
            id: "status",
            name: "Check runner status",
            description: "Show health and status of all runner instances",
            parameters: [
                RunnerActionParameter(name: "count", type: .integer, description: "Number of runners to check", required: false, defaultValue: "2"),
                RunnerActionParameter(name: "name-prefix", type: .string, description: "Runner name prefix", required: false, defaultValue: "macmini"),
            ],
            availableFromStates: [.configured, .running, .stopped]
        ),
        RunnerAction(
            id: "clean",
            name: "Clean workspace",
            description: "Remove build artifacts and free disk space",
            requiresConfirmation: true,
            parameters: [
                RunnerActionParameter(name: "workspace", type: .path, description: "Specific workspace path to clean", required: false),
                RunnerActionParameter(name: "aggressive", type: .boolean, description: "Aggressive cleanup (all caches, derived data)", required: false, defaultValue: "false"),
                RunnerActionParameter(name: "dry-run", type: .boolean, description: "Show what would be deleted without deleting", required: false, defaultValue: "false"),
            ],
            availableFromStates: [.built, .configured, .running, .stopped]
        ),
        RunnerAction(
            id: "provision-worker",
            name: "Provision worker profile",
            description: "Apply a worker profile (dry-run by default)",
            parameters: [
                RunnerActionParameter(name: "profile", type: .string, description: "Worker profile name", required: false, defaultValue: "build-worker"),
                RunnerActionParameter(name: "apply", type: .boolean, description: "Apply the plan (default is dry-run)", required: false, defaultValue: "false"),
                RunnerActionParameter(name: "yes", type: .boolean, description: "Auto-confirm privileged changes", required: false, defaultValue: "false"),
            ],
            availableFromStates: [.freshClone, .built, .configured, .running, .stopped]
        ),
    ]
    
    private init() {}
    
    /// Returns all actions available from the given state.
    public func availableActions(from state: RunnerState) -> [RunnerAction] {
        allActions.filter { $0.availableFromStates.contains(state) }
    }
    
    /// Returns all possible actions (for documentation).
    public func allActionsList() -> [RunnerAction] { allActions }
    
    /// Finds an action by ID.
    public func action(id: String) -> RunnerAction? {
        allActions.first { $0.id == id }
    }
}

// MARK: - Execution Result

/// The result of executing a runner action.
public struct RunnerActionResult: Sendable {
    public let actionID: String
    public let success: Bool
    public let message: String
    public let details: [String: String]
    public let newState: RunnerState?
    
    public init(
        actionID: String,
        success: Bool,
        message: String,
        details: [String: String] = [:],
        newState: RunnerState? = nil
    ) {
        self.actionID = actionID
        self.success = success
        self.message = message
        self.details = details
        self.newState = newState
    }
}

// MARK: - JSON Serialization

extension RunnerState {
    public func toJSON() -> [String: Any] {
        [
            "state": rawValue,
            "description": description,
            "possible_actions": RunnerActionDiscovery.shared.availableActions(from: self).map { $0.toJSON() }
        ]
    }
}

extension RunnerAction {
    public func toJSON() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "description": description,
            "requires_confirmation": requiresConfirmation,
            "requires_token": requiresToken,
            "parameters": parameters.map { $0.toJSON() }
        ]
    }
}

extension RunnerActionParameter {
    public func toJSON() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "type": type.rawValue,
            "description": description,
            "required": required
        ]
        if let defaultValue {
            dict["default_value"] = defaultValue
        }
        return dict
    }
}

extension RunnerActionResult {
    public func toJSON() -> [String: Any] {
        var dict: [String: Any] = [
            "action_id": actionID,
            "success": success,
            "message": message,
            "details": details
        ]
        if let newState {
            dict["new_state"] = newState.rawValue
        }
        return dict
    }
}
