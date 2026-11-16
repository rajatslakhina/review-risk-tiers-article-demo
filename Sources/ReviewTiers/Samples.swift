/// Realistic iOS changes used by the demo app and pinned by tests.
public enum SampleChanges {
    public static let lead = Author("rajat", trusted: true)
    public static let contractor = Author("guest-dev", trusted: false)

    public static let all: [Change] = [
        Change(id: "copy-typo", title: "Fix a typo in onboarding copy", author: lead,
               files: [ChangedFile("App/Resources/Localizable.xcstrings", added: 1, removed: 1)], agentWritten: true),
        Change(id: "camera-prompt", title: "Reword the camera permission prompt", author: lead,
               files: [ChangedFile("App/Info.plist", added: 1, removed: 1)], agentWritten: true),
        Change(id: "camera-prompt-fr", title: "Translate the camera prompt into French", author: lead,
               files: [ChangedFile("App/Resources/InfoPlist.xcstrings", added: 4, removed: 0)], agentWritten: true),
        Change(id: "unread-flagged", title: "Add an Unread filter behind a flag", author: lead,
               files: [ChangedFile("Features/Inbox/InboxFilter.swift", added: 41, removed: 0),
                       ChangedFile("Features/Inbox/InboxView.swift", added: 12, removed: 0)],
               behindFlag: true, agentWritten: true),
        Change(id: "unread-edit", title: "Change the default Inbox sort", author: lead,
               files: [ChangedFile("Features/Inbox/InboxView.swift", added: 6, removed: 4)],
               behindFlag: true, agentWritten: true),
        Change(id: "swiftdata-v3", title: "Add the SwiftData V3 schema migration", author: lead,
               files: [ChangedFile("Persistence/SchemaMigrationV3.swift", added: 88, removed: 0)],
               behindFlag: true, agentWritten: true),
        Change(id: "ci-xcode", title: "Bump Xcode in CI", author: lead,
               files: [ChangedFile(".github/workflows/ci.yml", added: 1, removed: 1)], agentWritten: true),
        Change(id: "guest-docs", title: "Clarify the README setup steps", author: contractor,
               files: [ChangedFile("README.md", added: 5, removed: 2)]),
    ]

    public static func change(_ id: String) -> Change? { all.first { $0.id == id } }

    /// Reviewer output for four rounds on one agent-written PR: the same old bug keeps coming back.
    public static let reviewRounds: [[Finding]] = [
        [Finding("force-unwrap", "Features/Inbox/InboxFilter.swift", line: 18),
         Finding("force-unwrap", "Features/Inbox/InboxFilter.swift", line: 33),
         Finding("missing-label", "Features/Inbox/InboxView.swift", line: 51, .nit)],
        [Finding("force-unwrap", "Features/Inbox/InboxFilter.swift", line: 18),
         Finding("main-actor-hop", "Features/Inbox/InboxStore.swift", line: 72, .preExisting),
         Finding("stale-cache", "Features/Inbox/InboxStore.swift", line: 90)],
        [Finding("stale-cache", "Features/Inbox/InboxStore.swift", line: 90),
         Finding("stale-cache", "Features/Inbox/InboxStore.swift", line: 104)],
        [Finding("stale-cache", "Features/Inbox/InboxStore.swift", line: 118)],
    ]

    /// Files the author touched before each round. Diff-only rounds only post new findings in these.
    public static let reviewRoundChangedFiles: [Set<String>] = [
        ["Features/Inbox/InboxFilter.swift", "Features/Inbox/InboxView.swift"],
        ["Features/Inbox/InboxFilter.swift", "Features/Inbox/InboxStore.swift"],
        ["Features/Inbox/InboxStore.swift"],
        ["Features/Inbox/InboxStore.swift"],
    ]
}
