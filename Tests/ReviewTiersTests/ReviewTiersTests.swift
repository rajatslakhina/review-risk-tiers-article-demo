import XCTest
@testable import ReviewTiers

final class GlobTests: XCTestCase {
    func testDoubleStarMatchesZeroOrMoreSegments() {
        let glob = Glob("**/Info.plist")
        XCTAssertTrue(glob.matches("Info.plist"))
        XCTAssertTrue(glob.matches("App/Info.plist"))
        XCTAssertTrue(glob.matches("Targets/Widget/Info.plist"))
        XCTAssertFalse(glob.matches("App/InfoPlist.xcstrings"))
        XCTAssertFalse(glob.matches("App/Info.plist.bak"))
    }

    func testStarStaysInsideOneSegment() {
        let glob = Glob("Sources/*.swift")
        XCTAssertTrue(glob.matches("Sources/A.swift"))
        XCTAssertFalse(glob.matches("Sources/Sub/A.swift"))
    }

    func testTrailingDoubleStarAndDirectoryBundles() {
        XCTAssertTrue(Glob(".github/workflows/**").matches(".github/workflows/ci.yml"))
        XCTAssertFalse(Glob(".github/workflows/**").matches(".github/CODEOWNERS"))
        XCTAssertTrue(Glob("**/*.xcdatamodeld/**").matches("Persistence/Model.xcdatamodeld/Model 2.xcdatamodel/contents"))
    }

    func testQuestionMarkAndBacktracking() {
        XCTAssertTrue(Glob("**/*Migration*.swift").matches("Persistence/SchemaMigrationV3.swift"))
        XCTAssertTrue(Glob("a?c").matches("abc"))
        XCTAssertFalse(Glob("a?c").matches("ac"))
        XCTAssertTrue(Glob("*a*a*a").matches("aaaa"))
        XCTAssertFalse(Glob("*a*a*a*b").matches("aaaaaaaaaa"))
    }

    func testEmptyInputs() {
        XCTAssertTrue(Glob("").matches(""))
        XCTAssertFalse(Glob("").matches("a"))
        XCTAssertTrue(Glob("**").matches(""))
    }
}

final class RiskPolicyTests: XCTestCase {
    let policy = RiskPolicy.iOSDefault

    private func classify(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> Classification {
        let change = try XCTUnwrap(SampleChanges.change(id), file: file, line: line)
        return policy.classify(change)
    }

    func testStringCatalogCopyMergesOnGreen() throws {
        let c = try classify("copy-typo")
        XCTAssertEqual(c.tier, .low)
        XCTAssertTrue(c.canMergeOnGreen)
    }

    func testInfoPlistCopyIsNeverLow() throws {
        let c = try classify("camera-prompt")
        XCTAssertEqual(c.tier, .medium)
        XCTAssertEqual(c.requiredHumanApprovals, 1)
        XCTAssertTrue(c.perspectives.contains(.appReview))
    }

    func testLocalizedPermissionPromptsAreNotOrdinaryCatalogCopy() throws {
        let c = try classify("camera-prompt-fr")
        XCTAssertEqual(c.files.first?.reason.contains("permission prompts"), true)
        XCTAssertEqual(c.requiredHumanApprovals, 1)
        XCTAssertFalse(c.canMergeOnGreen)
    }

    func testAdditiveFlaggedWorkDropsToLow() throws {
        let c = try classify("unread-flagged")
        XCTAssertEqual(c.tier, .low)
        XCTAssertEqual(c.requiredHumanApprovals, 0)
        XCTAssertEqual(ReviewerPrompt.perspectives(for: c), [.correctness])
    }

    func testEditingExistingLinesBehindAFlagStaysMedium() throws {
        let c = try classify("unread-edit")
        XCTAssertEqual(c.tier, .medium)
        XCTAssertEqual(c.requiredHumanApprovals, 1)
        XCTAssertTrue(ReviewerPrompt.perspectives(for: c).contains(.accessibility))
    }

    func testFlagNeverDowngradesAnAlwaysHumanPath() throws {
        let c = try classify("swiftdata-v3")
        XCTAssertEqual(c.tier, .high)
        XCTAssertEqual(c.requiredHumanApprovals, 2)
        XCTAssertTrue(c.perspectives.contains(.dataMigration))
    }

    func testFlagNeverDowngradesAnAlwaysHumanMediumPath() {
        let change = Change(id: "x", title: "Add a URL scheme", author: SampleChanges.lead,
                            files: [ChangedFile("App/Info.plist", added: 6, removed: 0)], behindFlag: true)
        let c = policy.classify(change)
        XCTAssertEqual(c.tier, .medium)
        XCTAssertEqual(c.requiredHumanApprovals, 1)
    }

    func testCIWorkflowNeedsTwoPeople() throws {
        let c = try classify("ci-xcode")
        XCTAssertEqual(c.tier, .high)
        XCTAssertEqual(c.requiredHumanApprovals, 2)
    }

    func testUntrustedAuthorNeverGetsTheZeroHumanPath() throws {
        let c = try classify("guest-docs")
        XCTAssertEqual(c.tier, .low)
        XCTAssertEqual(c.requiredHumanApprovals, 1)
        XCTAssertTrue(c.requiresNonAuthorApproval)
    }

    func testHighestFileSetsTheTier() {
        let change = Change(id: "mix", title: "Docs plus a purchase fix", author: SampleChanges.lead,
                            files: [ChangedFile("docs/setup.md", added: 3, removed: 0),
                                    ChangedFile("App/Purchases/Restore.swift", added: 2, removed: 2)])
        let c = policy.classify(change)
        XCTAssertEqual(c.tier, .high)
        XCTAssertEqual(c.files.map(\.tier), [.low, .high])
        XCTAssertTrue(c.perspectives.contains(.money))
    }

    func testEmptyChangeIsLowAndNoted() {
        let c = policy.classify(Change(id: "e", title: "Empty", author: SampleChanges.lead, files: []))
        XCTAssertEqual(c.tier, .low)
        XCTAssertTrue(c.notes.contains("Empty change."))
    }

    func testReviewerAndAgentInstructionsAlwaysNeedAPerson() {
        for path in ["REVIEW.md", "Features/Inbox/REVIEW.md", "CLAUDE.md", "AGENTS.md"] {
            let change = Change(id: path, title: "Edit \(path)", author: SampleChanges.lead,
                                files: [ChangedFile(path, added: 2, removed: 0)], agentWritten: true)
            let c = policy.classify(change)
            XCTAssertEqual(c.requiredHumanApprovals, 1, path)
            XCTAssertFalse(c.canMergeOnGreen, path)
        }
        XCTAssertEqual(policy.rule(for: "docs/setup.md")?.tier, .low)
    }

    func testLegacyAndCustomNamedPermissionFilesNeverMergeOnGreen() {
        for path in ["App/fr.lproj/InfoPlist.strings", "Targets/Widget/MyApp-Info.plist"] {
            let change = Change(id: path, title: "Edit \(path)", author: SampleChanges.lead,
                                files: [ChangedFile(path, added: 2, removed: 0)],
                                behindFlag: true, agentWritten: true)
            let c = policy.classify(change)
            XCTAssertEqual(c.tier, .medium, path)
            XCTAssertEqual(c.requiredHumanApprovals, 1, path)
        }
    }

    func testVersionedSchemaFileIsHighEvenWhenFlagged() {
        let change = Change(id: "s", title: "Add a field to SchemaV4", author: SampleChanges.lead,
                            files: [ChangedFile("Persistence/InboxSchemaV4.swift", added: 3, removed: 0)],
                            behindFlag: true, agentWritten: true)
        XCTAssertEqual(policy.classify(change).tier, .high)
    }

    func testFirstMatchingRuleWins() {
        XCTAssertEqual(policy.rule(for: "App/Resources/InfoPlist.xcstrings")?.tier, .medium)
        XCTAssertEqual(policy.rule(for: "App/Resources/Localizable.xcstrings")?.tier, .low)
        XCTAssertNil(policy.rule(for: "Features/Inbox/InboxFilter.swift"))
    }

    func testEverySampleIsPinned() {
        let expected: [String: (RiskTier, Int)] = [
            "copy-typo": (.low, 0), "camera-prompt": (.medium, 1), "camera-prompt-fr": (.medium, 1),
            "unread-flagged": (.low, 0), "unread-edit": (.medium, 1), "swiftdata-v3": (.high, 2),
            "ci-xcode": (.high, 2), "guest-docs": (.low, 1),
        ]
        XCTAssertEqual(SampleChanges.all.count, expected.count)
        for change in SampleChanges.all {
            let c = policy.classify(change)
            XCTAssertEqual(c.tier, expected[change.id]?.0, change.id)
            XCTAssertEqual(c.requiredHumanApprovals, expected[change.id]?.1, change.id)
        }
    }
}

final class MergeGateTests: XCTestCase {
    let policy = RiskPolicy.iOSDefault

    func testAgentApprovalNeverFillsAHumanSlot() throws {
        let change = try XCTUnwrap(SampleChanges.change("camera-prompt"))
        let verdict = MergeGate.evaluate(policy.classify(change), change: change,
                                         approvals: [Approval("claude", .agent, commit: "abc")],
                                         headCommit: "abc", ciGreen: true, openFindings: 0)
        XCTAssertFalse(verdict.isMergeable)
        XCTAssertTrue(verdict.reasons.contains { $0.contains("has 0") })
    }

    func testAuthorWhoDirectedTheAgentCanBeTheOneHuman() throws {
        let change = try XCTUnwrap(SampleChanges.change("camera-prompt"))
        let verdict = MergeGate.evaluate(policy.classify(change), change: change,
                                         approvals: [Approval("rajat", .human, commit: "abc")],
                                         headCommit: "abc", ciGreen: true, openFindings: 0)
        XCTAssertEqual(verdict, .mergeable)
    }

    func testHandWrittenAuthorCannotBeTheirOwnReviewer() {
        let change = Change(id: "h", title: "Reword the camera prompt by hand", author: SampleChanges.lead,
                            files: [ChangedFile("App/Info.plist", added: 1, removed: 1)], agentWritten: false)
        let c = policy.classify(change)
        let selfOnly = MergeGate.evaluate(c, change: change,
                                          approvals: [Approval("rajat", .human, commit: "h")],
                                          headCommit: "h", ciGreen: true, openFindings: 0)
        XCTAssertFalse(selfOnly.isMergeable)
        XCTAssertTrue(selfOnly.reasons.contains { $0.contains("their own approval doesn't count") })
        let withPeer = MergeGate.evaluate(c, change: change,
                                          approvals: [Approval("rajat", .human, commit: "h"),
                                                      Approval("mei", .human, commit: "h")],
                                          headCommit: "h", ciGreen: true, openFindings: 0)
        XCTAssertEqual(withPeer, .mergeable)
    }

    func testApprovalCoversOneCommit() throws {
        let change = try XCTUnwrap(SampleChanges.change("camera-prompt"))
        let verdict = MergeGate.evaluate(policy.classify(change), change: change,
                                         approvals: [Approval("rajat", .human, commit: "abc")],
                                         headCommit: "def", ciGreen: true, openFindings: 0)
        XCTAssertFalse(verdict.isMergeable)
        XCTAssertTrue(verdict.reasons.contains { $0.contains("Stale (older commit): rajat") })
    }

    func testDuplicateApprovalsFromOnePersonCountOnce() throws {
        let change = try XCTUnwrap(SampleChanges.change("ci-xcode"))
        let verdict = MergeGate.evaluate(policy.classify(change), change: change,
                                         approvals: [Approval("rajat", .human, commit: "h"),
                                                     Approval("rajat", .human, commit: "h")],
                                         headCommit: "h", ciGreen: true, openFindings: 0)
        XCTAssertFalse(verdict.isMergeable)
    }

    func testUntrustedAuthorCannotSelfApprove() throws {
        let change = try XCTUnwrap(SampleChanges.change("guest-docs"))
        let c = policy.classify(change)
        let selfOnly = MergeGate.evaluate(c, change: change,
                                          approvals: [Approval("guest-dev", .human, commit: "h")],
                                          headCommit: "h", ciGreen: true, openFindings: 0)
        XCTAssertFalse(selfOnly.isMergeable)
        let withOwner = MergeGate.evaluate(c, change: change,
                                           approvals: [Approval("rajat", .human, commit: "h")],
                                           headCommit: "h", ciGreen: true, openFindings: 0)
        XCTAssertEqual(withOwner, .mergeable)
    }

    func testRedCIAndOpenFindingsBlockEvenLowTier() throws {
        let change = try XCTUnwrap(SampleChanges.change("copy-typo"))
        let c = policy.classify(change)
        XCTAssertEqual(MergeGate.evaluate(c, change: change, approvals: [], headCommit: "h",
                                          ciGreen: true, openFindings: 0), .mergeable)
        let blocked = MergeGate.evaluate(c, change: change, approvals: [], headCommit: "h",
                                         ciGreen: false, openFindings: 2)
        XCTAssertEqual(blocked.reasons.count, 2)
    }
}

final class ReviewLoopTests: XCTestCase {
    func testSampleRoundsStepBackAtTheCap() {
        var loop = ReviewLoop()
        var outcomes: [ReviewLoop.Round] = []
        for (index, reported) in SampleChanges.reviewRounds.enumerated() {
            let changed = SampleChanges.reviewRoundChangedFiles.indices.contains(index)
                ? SampleChanges.reviewRoundChangedFiles[index] : nil
            if let round = loop.record(reported, changedFiles: changed) { outcomes.append(round) }
        }
        XCTAssertEqual(outcomes.count, 3, "the fourth round never runs")
        XCTAssertEqual(outcomes.map(\.action), [.continue, .continue, .stepBack])
        XCTAssertEqual(outcomes.map(\.scope), [.wholeChange, .wholeChange, .newDiffOnly])
        XCTAssertEqual(outcomes.map(\.suppressedRepeats), [0, 1, 1])
        XCTAssertEqual(outcomes.map(\.stillOpen), [0, 1, 1])
        XCTAssertEqual(outcomes.map(\.outOfScope), [0, 0, 0])
        XCTAssertEqual(outcomes.first?.classes["force-unwrap"], 2)
        XCTAssertTrue(loop.isFinished)
        XCTAssertNil(loop.record([]))
    }

    func testUnfixedImportantRepeatNeverPasses() {
        var loop = ReviewLoop()
        let bug = Finding("force-unwrap", "A.swift", line: 9)
        XCTAssertEqual(loop.record([bug])?.action, .continue)
        let second = loop.record([bug])
        XCTAssertEqual(second?.newFindings.count, 0)
        XCTAssertEqual(second?.stillOpen, 1)
        XCTAssertEqual(second?.action, .continue)
        XCTAssertEqual(loop.record([])?.action, .pass)
    }

    func testDiffOnlyRoundDropsFindingsOutsideTheNewDiff() {
        var loop = ReviewLoop(roundCap: 5, fullReviewRounds: 1)
        loop.record([Finding("leak", "A.swift", line: 1)], changedFiles: ["B.swift"])
        let round = loop.record([Finding("stale-cache", "A.swift", line: 40),
                                 Finding("race", "B.swift", line: 2)], changedFiles: ["B.swift"])
        XCTAssertEqual(round?.scope, .newDiffOnly)
        XCTAssertEqual(round?.outOfScope, 1)
        XCTAssertEqual(round?.newFindings.map(\.file), ["B.swift"])
    }

    func testUnfixedBugInAnUntouchedFileStaysOpenInADiffOnlyRound() {
        var loop = ReviewLoop(roundCap: 5, fullReviewRounds: 1)
        let bug = Finding("force-unwrap", "A.swift", line: 9)
        loop.record([bug])
        let round = loop.record([bug], changedFiles: ["B.swift"])
        XCTAssertEqual(round?.outOfScope, 0)
        XCTAssertEqual(round?.stillOpen, 1)
        XCTAssertEqual(round?.action, .continue)
    }

    func testOnlyNitsOrPreExistingPass() {
        var loop = ReviewLoop()
        let round = loop.record([Finding("naming", "A.swift", line: 1, .nit),
                                 Finding("old-bug", "B.swift", line: 2, .preExisting)])
        XCTAssertEqual(round?.action, .pass)
    }

    func testRepeatWithinOneRoundIsSuppressed() {
        var loop = ReviewLoop()
        let f = Finding("leak", "A.swift", line: 3)
        let round = loop.record([f, f])
        XCTAssertEqual(round?.newFindings.count, 1)
        XCTAssertEqual(round?.suppressedRepeats, 1)
    }

    func testCapOfOneAndInvalidInputs() {
        var loop = ReviewLoop(roundCap: 0, fullReviewRounds: -1)
        XCTAssertEqual(loop.roundCap, 1)
        XCTAssertEqual(loop.nextScope, .newDiffOnly)
        XCTAssertEqual(loop.record([Finding("x", "A.swift", line: 1)])?.action, .stepBack)
    }
}

final class ReviewerPromptTests: XCTestCase {
    func testPromptCarriesEvidenceAndNoApprovalRules() throws {
        let change = try XCTUnwrap(SampleChanges.change("swiftdata-v3"))
        let c = RiskPolicy.iOSDefault.classify(change)
        let prompt = ReviewerPrompt.build(for: change, c, perspective: .dataMigration)
        XCTAssertTrue(prompt.contains("Risk tier: high"))
        XCTAssertTrue(prompt.contains("Persistence/SchemaMigrationV3.swift (+88 −0)"))
        XCTAssertTrue(prompt.contains("Cite a file and line"))
        XCTAssertTrue(prompt.contains("never approvals"))
    }

    func testHighTierGetsEveryLensItsPathsAskedFor() throws {
        let change = try XCTUnwrap(SampleChanges.change("swiftdata-v3"))
        let lenses = ReviewerPrompt.perspectives(for: RiskPolicy.iOSDefault.classify(change))
        XCTAssertEqual(lenses, [.correctness, .concurrency, .dataMigration])
    }
}
