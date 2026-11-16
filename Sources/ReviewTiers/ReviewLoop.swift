/// One finding from an AI reviewer.
public struct Finding: Sendable, Equatable, Hashable {
    public enum Tag: String, Sendable { case important = "Important", nit = "Nit", preExisting = "Pre-existing" }

    /// The class of bug ("force-unwrap", "main-actor-hop"). The author fixes the class, not one line.
    public let kind: String
    public let file: String
    public let line: Int
    public let tag: Tag

    public init(_ kind: String, _ file: String, line: Int, _ tag: Tag = .important) {
        self.kind = kind
        self.file = file
        self.line = line
        self.tag = tag
    }

    /// Identity used to suppress repeats across rounds.
    public var fingerprint: String { "\(kind)@\(file):\(line)" }
}

/// Keeps an agent author and an agent reviewer from keeping each other busy all night.
///
/// - Round cap: when findings are still arriving at the end of `roundCap`, the reviewer asks the
///   author to step back and reconsider the approach instead of running another round.
/// - Diff-only: after `fullReviewRounds`, only files changed since the last round are re-reviewed
///   (file granularity, when the caller passes `changedFiles`).
/// - No repeats: findings already posted are never posted again, but an Important one reported
///   again is still open and still blocks a pass.
/// - Classes: new findings are grouped by kind, so every instance gets fixed together.
public struct ReviewLoop: Sendable {
    public enum Scope: String, Sendable { case wholeChange = "whole change", newDiffOnly = "new diff only" }
    public enum Action: String, Sendable { case `continue` = "Fix and re-review", pass = "Pass", stepBack = "Step back" }

    public struct Round: Sendable, Equatable {
        public let number: Int
        public let scope: Scope
        public let newFindings: [Finding]
        public let suppressedRepeats: Int
        /// Important findings reported again this round: not re-posted, but still open.
        public let stillOpen: Int
        /// Findings dropped because a diff-only round only looks at files changed since the last round.
        public let outOfScope: Int
        /// Kind → count of new instances.
        public let classes: [String: Int]
        public let action: Action
    }

    public let roundCap: Int
    public let fullReviewRounds: Int
    public private(set) var rounds: [Round] = []
    private var posted: Set<String> = []

    public init(roundCap: Int = 3, fullReviewRounds: Int = 2) {
        self.roundCap = max(1, roundCap)
        self.fullReviewRounds = max(0, fullReviewRounds)
    }

    public var isFinished: Bool {
        guard let last = rounds.last else { return false }
        return last.action != .continue
    }

    /// The scope the next round should review.
    public var nextScope: Scope {
        rounds.count + 1 > fullReviewRounds ? .newDiffOnly : .wholeChange
    }

    /// Records what the reviewer reported this round. Returns nil once the loop has finished.
    ///
    /// - Parameter changedFiles: files touched since the previous round. In a diff-only round,
    ///   findings in any other file are dropped (counted in `outOfScope`). Pass nil to keep all.
    @discardableResult
    public mutating func record(_ reported: [Finding], changedFiles: Set<String>? = nil) -> Round? {
        guard !isFinished else { return nil }
        let number = rounds.count + 1
        let scope = nextScope

        var fresh: [Finding] = []
        var seenThisRound: Set<String> = []
        var repeats = 0
        var outOfScope = 0
        var reopened: Set<String> = []
        for finding in reported {
            let key = finding.fingerprint
            if posted.contains(key) || seenThisRound.contains(key) {
                // Repeats are checked before the scope filter: an unfixed bug in a file nobody
                // touched is still open, not out of scope. It isn't re-posted, but it blocks a pass.
                repeats += 1
                if posted.contains(key), finding.tag == .important { reopened.insert(key) }
            } else if scope == .newDiffOnly, let changedFiles, !changedFiles.contains(finding.file) {
                // A diff-only round doesn't post new findings outside the new diff.
                outOfScope += 1
            } else {
                seenThisRound.insert(key)
                fresh.append(finding)
            }
        }
        posted.formUnion(seenThisRound)

        var classes: [String: Int] = [:]
        for finding in fresh { classes[finding.kind, default: 0] += 1 }

        let blocking = fresh.contains { $0.tag == .important } || !reopened.isEmpty
        let action: Action
        if !blocking {
            action = .pass
        } else if number >= roundCap {
            action = .stepBack
        } else {
            action = .continue
        }

        let round = Round(number: number, scope: scope, newFindings: fresh,
                          suppressedRepeats: repeats, stillOpen: reopened.count, outOfScope: outOfScope,
                          classes: classes, action: action)
        rounds.append(round)
        return round
    }
}
