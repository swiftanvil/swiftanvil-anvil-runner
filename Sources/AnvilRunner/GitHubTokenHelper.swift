import Foundation

/// Errors related to GitHub token acquisition for runner registration.
public enum GitHubTokenError: Error, CustomStringConvertible {
    case ghNotInstalled
    case insufficientScope(required: String, provided: [String])
    case apiFailed(Int32, String)
    case orgLevelNotSupported

    public var description: String {
        switch self {
        case .ghNotInstalled:
            return "GitHub CLI (gh) is not installed. Install it or provide a token via --token."
        case .insufficientScope(let required, let provided):
            return """
            GitHub token is missing required scope '\(required)'.
            Current scopes: \(provided.joined(separator: ", ")).

            To create a token with the required scope, visit:
              https://github.com/settings/tokens/new?scopes=\(required.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? required),repo&description=Anvil%20Runner%20Setup

            Then re-run with:
              export ANVIL_RUNNER_TOKEN=<your-pat>
              anvil-runner setup --repo <url> --count <n>
            """
        case .apiFailed(let code, let msg):
            return "GitHub API call failed (exit \(code)): \(msg)"
        case .orgLevelNotSupported:
            return "Org-level runner registration requires a token with 'admin:org' scope."
        }
    }
}

/// Helps acquire GitHub Actions runner registration tokens.
public enum GitHubTokenHelper {
    /// Parses a GitHub URL to determine if it refers to an organization or a repository.
    public static func parseURL(_ url: String) -> (type: String, owner: String, repo: String?)? {
        // Supported formats:
        // https://github.com/my-org
        // https://github.com/my-org/my-repo
        // git@github.com:my-org/my-repo.git
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("https://github.com/") {
            let path = String(trimmed.dropFirst("https://github.com/".count))
                .replacingOccurrences(of: ".git", with: "")
            let parts = path.split(separator: "/", omittingEmptySubsequences: true)
            if parts.count == 1 {
                return ("org", String(parts[0]), nil)
            } else if parts.count >= 2 {
                return ("repo", String(parts[0]), String(parts[1]))
            }
        }

        if trimmed.hasPrefix("git@github.com:") {
            let path = String(trimmed.dropFirst("git@github.com:".count))
                .replacingOccurrences(of: ".git", with: "")
            let parts = path.split(separator: "/", omittingEmptySubsequences: true)
            if parts.count >= 2 {
                return ("repo", String(parts[0]), String(parts[1]))
            }
        }

        return nil
    }

    /// Returns the current `gh` token scopes, or nil if `gh` is not available.
    public static func ghScopes() -> [String]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["gh", "auth", "status"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard task.terminationStatus == 0 else { return nil }

        // Parse line: "Token scopes: 'gist', 'read:org', 'repo'"
        for line in out.components(separatedBy: .newlines) {
            if let range = line.range(of: "Token scopes:") {
                let scopesPart = String(line[range.upperBound...])
                return scopesPart
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }
                    .filter { !$0.isEmpty }
            }
        }
        return []
    }

    /// Returns true if the current `gh` token has the required scope.
    public static func ghHasScope(_ scope: String) -> Bool {
        guard let scopes = ghScopes() else { return false }
        return scopes.contains(scope)
    }

    /// Generates a runner registration token using `gh api`.
    ///
    /// - Parameters:
    ///   - url: Repository or organization URL.
    ///   - token: Optional explicit token. If nil, uses `gh`'s current authentication.
    /// - Returns: The registration token string.
    public static func generateRegistrationToken(for url: String, token: String? = nil) throws -> String {
        guard let parsed = parseURL(url) else {
            throw RunnerError.configurationFailed(reason: "Unsupported GitHub URL: \(url)")
        }

        let needsOrgScope = parsed.type == "org"
        let requiredScope = needsOrgScope ? "admin:org" : "repo"

        // Validate scope unless an explicit token is provided.
        if token == nil, !ghHasScope(requiredScope) {
            throw GitHubTokenError.insufficientScope(
                required: requiredScope,
                provided: ghScopes() ?? []
            )
        }

        var args = ["api", "-X", "POST"]
        if let token = token {
            args.append(contentsOf: ["-H", "Authorization: token \(token)"])
        }

        if parsed.type == "org" {
            args.append("/orgs/\(parsed.owner)/actions/runners/registration-token")
        } else if let repo = parsed.repo {
            args.append("/repos/\(parsed.owner)/\(repo)/actions/runners/registration-token")
        } else {
            throw GitHubTokenError.orgLevelNotSupported
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["gh"] + args
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            throw GitHubTokenError.ghNotInstalled
        }

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard task.terminationStatus == 0 else {
            throw GitHubTokenError.apiFailed(task.terminationStatus, err.isEmpty ? out : err)
        }

        // Parse JSON response for .token field.
        guard let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let registrationToken = json["token"] as? String else {
            throw GitHubTokenError.apiFailed(0, "Could not parse registration token from response: \(out)")
        }

        return registrationToken
    }
}
