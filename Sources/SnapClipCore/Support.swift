import Foundation

/// Official sponsorship channel exposed by `snapclip donate`.
public struct SupportChannel: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: String

    public init(id: String, name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}

/// Structured output returned by `snapclip donate --json`.
public struct DonateReport: Codable, Equatable, Sendable {
    public let url: String
    public let githubSponsors: String
    public let opened: Bool
    public let channels: [SupportChannel]

    enum CodingKeys: String, CodingKey {
        case url
        case githubSponsors = "github_sponsors"
        case opened
        case channels
    }

    public init(url: String, githubSponsors: String, opened: Bool, channels: [SupportChannel]) {
        self.url = url
        self.githubSponsors = githubSponsors
        self.opened = opened
        self.channels = channels
    }
}

/// Resolves and validates sponsorship links for SnapClip.
public enum SnapClipSupport {
    public static let githubSponsorsURL = "https://github.com/sponsors/aklkbqx"

    /// Validates an optional donation channel name and returns the support report.
    public static func buildReport(channel: String? = nil, opened: Bool = false) throws -> DonateReport {
        if let channel {
            let normalized = channel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "", "github", "sponsors", "sponsor":
                break
            default:
                throw SupportError.unknownChannel(channel)
            }
        }
        return DonateReport(
            url: githubSponsorsURL,
            githubSponsors: githubSponsorsURL,
            opened: opened,
            channels: [
                SupportChannel(
                    id: "github",
                    name: "GitHub Sponsors",
                    url: githubSponsorsURL
                )
            ]
        )
    }
}

/// Errors raised when selecting an unsupported donation channel.
public enum SupportError: LocalizedError, Equatable {
    case unknownChannel(String)

    public var errorDescription: String? {
        switch self {
        case .unknownChannel(let channel):
            return "Unknown channel '\(channel)' (expected: github)"
        }
    }
}
