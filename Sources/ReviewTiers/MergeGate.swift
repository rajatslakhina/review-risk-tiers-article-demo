public struct Approval: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case human, agent }

    public let reviewer: String
    public let kind: Kind
    /// The exact commit the reviewer looked at. An approval covers that commit and nothing after it.
    public let commit: String

    public init(_ reviewer: String, _ kind: Kind, commit: String) {
        self.reviewer = reviewer
        self.kind = kind
        self.commit = commit
    }
}

public enum MergeVerdict: Sendable, Equatable {
    case mergeable
    case blocked([String])

    public var isMergeable: Bool { self == .mergeable }
    public var reasons: [String] {
        if case .blocked(let reasons) = self { return reasons }
        return []
    }
}

/// Decides whether a classified change can merge right now.
public enum MergeGate {
    public static func evaluate(
        _ classification: Classification,
        change: Change,
        approvals: [Approval],
        headCommit: String,
        ciGreen: Bool,
        openFindings: Int
    ) -> MergeVerdict {
        var reasons: [String] = []

        if !ciGreen { reasons.append("Required CI isn't green.") }
        if openFindings > 0 {
            reasons.append("\(openFindings) review finding\(openFindings == 1 ? "" : "s") still open: fix or resolve with a reason.")
        }

        // An agent's approval never fills a human slot.
        let humans = approvals.filter { $0.kind == .human }
        let current = humans.filter { $0.commit == headCommit }
        let stale = Set(humans.filter { $0.commit != headCommit }.map(\.reviewer))
            .subtracting(current.map(\.reviewer))

        var approvers = Set(current.map(\.reviewer))
        let author = change.author.handle

        // The person who directed an agent is on the hook for its PR and counts as a reviewer.
        // Someone approving their own hand-written code doesn't.
        let discountedSelfApproval = !change.agentWritten && approvers.remove(author) != nil

        let required = classification.requiredHumanApprovals
        if approvers.count < required {
            var line = "Needs \(required) human approval\(required == 1 ? "" : "s") on \(headCommit), has \(approvers.count)."
            if discountedSelfApproval {
                line += " \(author) wrote it by hand, so their own approval doesn't count."
            }
            if !stale.isEmpty {
                line += " Stale (older commit): \(stale.sorted().joined(separator: ", "))."
            }
            reasons.append(line)
        }

        if classification.requiresNonAuthorApproval, approvers.subtracting([author]).isEmpty {
            reasons.append("Author isn't trusted: a person other than \(author) must approve.")
        }

        return reasons.isEmpty ? .mergeable : .blocked(reasons)
    }
}
