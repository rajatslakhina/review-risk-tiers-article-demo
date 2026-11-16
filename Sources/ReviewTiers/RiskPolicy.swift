/// One line of the policy: "changes to these paths are at least this risky, and here's why".
public struct PathRule: Sendable, Equatable, Hashable {
    public let glob: Glob
    public let tier: RiskTier
    /// A person must approve, whatever the tier says. Owner-listed sensitive paths and CI live here.
    public let alwaysHuman: Bool
    public let perspectives: Set<ReviewPerspective>
    public let reason: String

    public init(_ pattern: String, _ tier: RiskTier, alwaysHuman: Bool = false,
                perspectives: Set<ReviewPerspective> = [], reason: String) {
        self.glob = Glob(pattern)
        self.tier = tier
        self.alwaysHuman = alwaysHuman
        self.perspectives = perspectives
        self.reason = reason
    }
}

public struct FileVerdict: Sendable, Equatable {
    public let file: ChangedFile
    public let tier: RiskTier
    public let alwaysHuman: Bool
    /// nil when no rule matched and the policy default applied.
    public let rule: PathRule?
    public let reason: String
}

public struct Classification: Sendable, Equatable {
    public let tier: RiskTier
    public let requiredHumanApprovals: Int
    /// At least one approval must come from a person other than the author.
    public let requiresNonAuthorApproval: Bool
    public let files: [FileVerdict]
    public let perspectives: [ReviewPerspective]
    public let notes: [String]

    /// True only when nobody has to look: the "merge on green" path.
    public var canMergeOnGreen: Bool { requiredHumanApprovals == 0 }
}

/// Risk-tiers a change from what it touches. The author's seniority is never an input;
/// trust only decides whether the lighter paths are available at all.
public struct RiskPolicy: Sendable {
    public let rules: [PathRule]
    public let defaultTier: RiskTier

    public init(rules: [PathRule], defaultTier: RiskTier = .medium) {
        self.rules = rules
        self.defaultTier = defaultTier
    }

    /// First matching rule wins, so order rules from most to least specific.
    public func rule(for path: String) -> PathRule? {
        rules.first { $0.glob.matches(path) }
    }

    public func classify(_ change: Change) -> Classification {
        var verdicts: [FileVerdict] = []
        var perspectives: Set<ReviewPerspective> = [.correctness]
        var notes: [String] = []

        for file in change.files {
            let rule = rule(for: file.path)
            var tier = rule?.tier ?? defaultTier
            var reason = rule?.reason ?? "ordinary product code"
            let alwaysHuman = rule?.alwaysHuman ?? false

            // Additive, flagged work can drop to low — but never on a path that always needs a person,
            // and never when it edits or deletes existing lines.
            if change.behindFlag, file.isAdditive, tier == .medium, !alwaysHuman {
                tier = .low
                reason += "; additive and behind a flag"
            }
            perspectives.formUnion(rule?.perspectives ?? [])
            verdicts.append(FileVerdict(file: file, tier: tier, alwaysHuman: alwaysHuman, rule: rule, reason: reason))
        }

        let tier = verdicts.map(\.tier).max() ?? .low
        var required = tier.baseHumanApprovals

        if verdicts.contains(where: \.alwaysHuman), required < 1 {
            required = 1
            notes.append("A path in this change always needs a person.")
        }

        let requiresNonAuthor = !change.author.isTrusted
        if requiresNonAuthor {
            if required < 1 { required = 1 }
            notes.append("\(change.author.handle) isn't on the trusted list: no zero-human path, and someone else must approve.")
        }

        if change.files.isEmpty {
            notes.append("Empty change.")
        }

        return Classification(
            tier: tier,
            requiredHumanApprovals: required,
            requiresNonAuthorApproval: requiresNonAuthor,
            files: verdicts,
            perspectives: perspectives.sorted(),
            notes: notes
        )
    }
}

public extension RiskPolicy {
    /// The iOS paths a green bot should never merge alone, plus the ones it safely can.
    /// Ordered most-specific first.
    ///
    /// Path rules are a floor, not the whole classifier: an `@Model` property added to an
    /// ordinarily named file still migrates the store. Pair this with a content-aware check.
    static let iOSDefault = RiskPolicy(rules: [
        // Pipelines: a workflow edit can skip checks or read secrets.
        PathRule(".github/workflows/**", .high, alwaysHuman: true, perspectives: [.security],
                 reason: "CI workflow: can skip checks or read signing secrets"),
        PathRule("ci_scripts/**", .high, alwaysHuman: true, perspectives: [.security],
                 reason: "Xcode Cloud script: runs with your signing identity"),
        PathRule("fastlane/**", .high, alwaysHuman: true, perspectives: [.security],
                 reason: "release lane: signing, upload and metadata"),

        // Things App Review, signing or the user's device keep forever.
        PathRule("**/*.entitlements", .high, alwaysHuman: true, perspectives: [.security, .appReview],
                 reason: "capabilities and signing"),
        PathRule("**/PrivacyInfo.xcprivacy", .high, alwaysHuman: true, perspectives: [.appReview],
                 reason: "privacy manifest: checked at upload and read by App Review"),
        PathRule("**/*.xcdatamodeld/**", .high, alwaysHuman: true, perspectives: [.dataMigration],
                 reason: "Core Data model: a shipped migration can't be turned off with a flag"),
        PathRule("**/*Migration*.swift", .high, alwaysHuman: true, perspectives: [.dataMigration, .concurrency],
                 reason: "persistence migration: runs once on every user's store"),
        PathRule("**/*Schema*.swift", .high, alwaysHuman: true, perspectives: [.dataMigration],
                 reason: "versioned SwiftData schema: changing it migrates every user's store"),
        PathRule("**/*.storekit", .high, alwaysHuman: true, perspectives: [.money],
                 reason: "StoreKit configuration"),
        PathRule("**/Purchases/**", .high, alwaysHuman: true, perspectives: [.money, .security],
                 reason: "in-app purchase and entitlement logic"),

        // "Copy" that isn't low risk on iOS.
        PathRule("**/Info.plist", .medium, alwaysHuman: true, perspectives: [.appReview, .security],
                 reason: "usage descriptions, URL schemes and ATS exceptions: App Review reads these"),
        PathRule("**/*Info.plist", .medium, alwaysHuman: true, perspectives: [.appReview, .security],
                 reason: "a target's Info.plist under a custom name: same keys, same review"),
        PathRule("**/InfoPlist.strings", .medium, alwaysHuman: true, perspectives: [.appReview],
                 reason: "legacy localized permission prompts in an .lproj folder"),
        PathRule("**/InfoPlist.xcstrings", .medium, alwaysHuman: true, perspectives: [.appReview],
                 reason: "localized permission prompts: the same strings as Info.plist, in every language"),
        PathRule("**/*.pbxproj", .medium, alwaysHuman: true, perspectives: [.security],
                 reason: "signing settings and build phases hide in the project file"),

        // The reviewer's and the agent's own instructions: editing them changes every future review.
        PathRule("**/REVIEW.md", .medium, alwaysHuman: true, perspectives: [.security],
                 reason: "reviewer instructions"),
        PathRule("**/CLAUDE.md", .medium, alwaysHuman: true, perspectives: [.security],
                 reason: "agent instructions"),
        PathRule("**/AGENTS.md", .medium, alwaysHuman: true, perspectives: [.security],
                 reason: "agent instructions"),

        // Ordinary code that still deserves a specific lens.
        PathRule("**/*View.swift", .medium, perspectives: [.accessibility],
                 reason: "SwiftUI view"),
        PathRule("**/*Actor.swift", .medium, perspectives: [.concurrency],
                 reason: "actor-isolated state"),

        // What can merge on green.
        PathRule("**/*.xcstrings", .low, reason: "in-app copy in a string catalog"),
        PathRule("**/*.md", .low, reason: "documentation"),
        PathRule("docs/**", .low, reason: "documentation"),
    ])
}
