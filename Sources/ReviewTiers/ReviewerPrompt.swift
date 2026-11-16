/// Builds the prompt for one AI reviewer pass. One perspective per pass keeps each reviewer
/// focused; the tier decides how many perspectives a change gets.
public enum ReviewerPrompt {
    /// Perspectives to run for a classification. Low-risk changes get a single correctness pass;
    /// anything higher gets every lens its paths asked for.
    public static func perspectives(for classification: Classification) -> [ReviewPerspective] {
        classification.tier == .low ? [.correctness] : classification.perspectives
    }

    /// The REVIEW.md-style rules every pass carries.
    public static let houseRules: [String] = [
        "Cite a file and line as evidence for every finding. Never infer a bug from a name.",
        "Tag each finding Important, Nit or Pre-existing. Pre-existing bugs are not the author's fault.",
        "Report at most 3 nits.",
        "When the same mistake appears more than once, name the class and list every instance.",
        "Start your summary with the number of findings. If there is nothing to fix, say so plainly.",
        "You post findings, never approvals. A person approves this change.",
    ]

    public static func focus(for perspective: ReviewPerspective) -> String {
        switch perspective {
        case .correctness:
            return "Does the change do what its title says, and does it break any caller?"
        case .security:
            return "Look for secrets, signing changes, weakened checks and new network or file access."
        case .concurrency:
            return "Look for actor reentrancy across await, main-actor hops and unchecked Sendable."
        case .accessibility:
            return "Check labels, Dynamic Type, contrast and VoiceOver order on every new view."
        case .appReview:
            return "Would App Review accept this? Check purpose strings, privacy manifest entries and declared capabilities against what the code actually does."
        case .dataMigration:
            return "Can every shipped store version open after this? Is the migration idempotent and safe to interrupt?"
        case .money:
            return "Can a user get something they didn't pay for, or pay for something they don't get?"
        }
    }

    public static func build(for change: Change, _ classification: Classification,
                             perspective: ReviewPerspective) -> String {
        var lines: [String] = []
        lines.append("You are reviewing \"\(change.title)\" as the \(perspective.title) reviewer.")
        lines.append("Risk tier: \(classification.tier). \(focus(for: perspective))")
        lines.append("")
        lines.append("Files in scope:")
        for verdict in classification.files {
            lines.append("- \(verdict.file.path) (+\(verdict.file.linesAdded) −\(verdict.file.linesRemoved)) — \(verdict.tier): \(verdict.reason)")
        }
        lines.append("")
        lines.append("Rules:")
        for rule in houseRules { lines.append("- \(rule)") }
        return lines.joined(separator: "\n")
    }
}
