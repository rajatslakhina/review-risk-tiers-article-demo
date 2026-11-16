/// How much human attention a change needs. The change sets the tier, not the author.
public enum RiskTier: Int, Comparable, CaseIterable, Sendable, CustomStringConvertible {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: RiskTier, rhs: RiskTier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Human approvals the tier asks for before any always-human or trust floor is applied.
    /// Low 0, medium 1, high 2 — the same split as the Claude Code team's table.
    public var baseHumanApprovals: Int { rawValue }

    public var description: String {
        switch self {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }
}

/// A lens an AI reviewer is asked to read the diff through.
public enum ReviewPerspective: String, CaseIterable, Sendable, Comparable {
    case correctness
    case security
    case concurrency
    case accessibility
    case appReview
    case dataMigration
    case money

    public static func < (lhs: ReviewPerspective, rhs: ReviewPerspective) -> Bool {
        let order = ReviewPerspective.allCases
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    public var title: String {
        switch self {
        case .correctness: return "Correctness"
        case .security: return "Security"
        case .concurrency: return "Concurrency"
        case .accessibility: return "Accessibility"
        case .appReview: return "App Review"
        case .dataMigration: return "Data migration"
        case .money: return "Purchases"
        }
    }
}

public struct ChangedFile: Sendable, Equatable, Hashable {
    public let path: String
    public let linesAdded: Int
    public let linesRemoved: Int

    public init(_ path: String, added: Int, removed: Int) {
        self.path = path
        self.linesAdded = max(0, added)
        self.linesRemoved = max(0, removed)
    }

    /// Pure addition: nothing existing was edited or deleted.
    public var isAdditive: Bool { linesRemoved == 0 && linesAdded > 0 }
}

public struct Author: Sendable, Equatable, Hashable {
    public let handle: String
    /// On the repo's trusted list (usually the owning team). Only trusted authors get the lighter paths.
    public let isTrusted: Bool

    public init(_ handle: String, trusted: Bool) {
        self.handle = handle
        self.isTrusted = trusted
    }
}

public struct Change: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// The human who wrote the code or directed the agent that did. They are on the hook for it.
    public let author: Author
    public let files: [ChangedFile]
    /// New behaviour ships dark behind a feature flag that can be turned off without a release.
    public let behindFlag: Bool
    /// An agent wrote the code and `author` directed it. Only then does the author's own
    /// approval count as one of the required reviews; on hand-written code it never does.
    public let agentWritten: Bool

    public init(id: String, title: String, author: Author, files: [ChangedFile],
                behindFlag: Bool = false, agentWritten: Bool = false) {
        self.id = id
        self.title = title
        self.author = author
        self.files = files
        self.behindFlag = behindFlag
        self.agentWritten = agentWritten
    }
}
