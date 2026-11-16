import SwiftUI
import ReviewTiers

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    /// `-tab loop` opens the review-loop tab, `-change <id>` opens one change. Used for screenshots.
    @State private var tab: String = UserDefaults.standard.string(forKey: "tab") ?? "changes"

    var body: some View {
        TabView(selection: $tab) {
            ChangesView(initialChange: UserDefaults.standard.string(forKey: "change"))
                .tabItem { Label("Changes", systemImage: "arrow.triangle.branch") }
                .tag("changes")
            ReviewLoopView()
                .tabItem { Label("Review loop", systemImage: "arrow.clockwise.circle") }
                .tag("loop")
        }
    }
}

// MARK: - Changes

struct ChangesView: View {
    let policy = RiskPolicy.iOSDefault
    @State private var path: [String]

    init(initialChange: String?) {
        _path = State(initialValue: initialChange.flatMap { SampleChanges.change($0) != nil ? [$0] : nil } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(SampleChanges.all) { change in
                        NavigationLink(value: change.id) {
                            ChangeRow(change: change, classification: policy.classify(change))
                        }
                    }
                } footer: {
                    Text("The change sets the tier, not the author. Rules: RiskPolicy.iOSDefault.")
                }
            }
            .navigationTitle("Review tiers")
            .navigationDestination(for: String.self) { id in
                if let change = SampleChanges.change(id) {
                    ChangeDetailView(change: change, classification: policy.classify(change))
                } else {
                    Text("Unknown change")
                }
            }
        }
    }
}

struct TierBadge: View {
    let tier: RiskTier

    var color: Color {
        switch tier {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    var body: some View {
        Text(tier.description.uppercased())
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("\(tier.description) risk")
    }
}

struct ChangeRow: View {
    let change: Change
    let classification: Classification

    var humans: String {
        classification.canMergeOnGreen ? "Merges on green" :
            "\(classification.requiredHumanApprovals) human\(classification.requiredHumanApprovals == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TierBadge(tier: classification.tier)
                Text(humans).font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(change.title).font(.body)
            Text(change.files.map(\.path).joined(separator: ", "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

struct ChangeDetailView: View {
    let change: Change
    let classification: Classification
    @State private var perspective: ReviewPerspective = .correctness

    var lenses: [ReviewPerspective] { ReviewerPrompt.perspectives(for: classification) }

    var body: some View {
        List {
            Section("Verdict") {
                HStack {
                    TierBadge(tier: classification.tier)
                    Text(classification.canMergeOnGreen ? "Merges once CI and AI review are green"
                         : "Needs \(classification.requiredHumanApprovals) human approval\(classification.requiredHumanApprovals == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Author: \(change.author.handle)\(change.author.isTrusted ? " (trusted)" : " (not trusted)")\(change.agentWritten ? " · directed an agent" : " · hand-written")\(change.behindFlag ? " · behind a flag" : "")")
                    .font(.footnote)
                ForEach(classification.notes, id: \.self) { note in
                    Label(note, systemImage: "person.fill.checkmark").font(.footnote)
                }
            }
            Section("Files") {
                ForEach(Array(classification.files.enumerated()), id: \.offset) { _, verdict in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            TierBadge(tier: verdict.tier)
                            if verdict.alwaysHuman {
                                Image(systemName: "person.badge.shield.checkmark")
                                    .accessibilityLabel("always needs a person")
                            }
                            Text("+\(verdict.file.linesAdded) −\(verdict.file.linesRemoved)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(verdict.file.path).font(.caption.monospaced())
                        Text(verdict.reason).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("AI reviewer prompt") {
                Picker("Perspective", selection: $perspective) {
                    ForEach(lenses, id: \.self) { Text($0.title).tag($0) }
                }
                Text(ReviewerPrompt.build(for: change, classification, perspective: perspective))
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(change.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // `-lens last` preselects the most specific lens, for screenshots.
            if UserDefaults.standard.string(forKey: "lens") == "last", let last = lenses.last {
                perspective = last
            }
        }
    }
}

// MARK: - Review loop

struct ReviewLoopView: View {
    @State private var loop = ReviewLoop()
    @State private var nextBatch = 0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                Section {
                    Text("An agent author and an agent reviewer can keep each other busy all night. Cap: \(loop.roundCap) rounds; whole change for the first \(loop.fullReviewRounds), then the new diff only; repeats never re-posted.")
                        .font(.footnote)
                }
                ForEach(loop.rounds, id: \.number) { round in
                    Section("Round \(round.number) · \(round.scope.rawValue)") {
                        ForEach(round.newFindings, id: \.fingerprint) { finding in
                            HStack(alignment: .firstTextBaseline) {
                                Text(finding.tag.rawValue)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(finding.tag == .important ? .red : .secondary)
                                    .frame(width: 78, alignment: .leading)
                                Text("\(finding.kind) — \((finding.file as NSString).lastPathComponent):\(finding.line)")
                                    .font(.caption.monospaced())
                            }
                        }
                        if round.suppressedRepeats > 0 {
                            Text("\(round.suppressedRepeats) repeat\(round.suppressedRepeats == 1 ? "" : "s") not re-posted\(round.stillOpen > 0 ? ", \(round.stillOpen) still open" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Classes: " + round.classes.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                        Label(round.action.rawValue,
                              systemImage: round.action == .stepBack ? "hand.raised.fill" :
                                (round.action == .pass ? "checkmark.seal.fill" : "arrow.clockwise"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(round.action == .stepBack ? .orange : .primary)
                            .id("action-\(round.number)")
                    }
                }
                Section {
                    Button(loop.isFinished ? "Loop finished" : "Run reviewer round \(loop.rounds.count + 1)") {
                        runNext()
                    }
                    .disabled(loop.isFinished || nextBatch >= SampleChanges.reviewRounds.count)
                    Button("Reset", role: .destructive) {
                        loop = ReviewLoop()
                        nextBatch = 0
                    }
                }
            }
            .navigationTitle("Review loop")
            .onAppear {
                if UserDefaults.standard.bool(forKey: "autorun"), loop.rounds.isEmpty {
                    while !loop.isFinished, nextBatch < SampleChanges.reviewRounds.count { runNext() }
                    // `-autorun YES` also scrolls to the final verdict, for screenshots.
                    if let last = loop.rounds.last?.number {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            proxy.scrollTo("action-\(last)", anchor: .center)
                        }
                    }
                }
            }
            }
        }
    }

    private func runNext() {
        guard nextBatch < SampleChanges.reviewRounds.count else { return }
        let changed = SampleChanges.reviewRoundChangedFiles.indices.contains(nextBatch)
            ? SampleChanges.reviewRoundChangedFiles[nextBatch] : nil
        loop.record(SampleChanges.reviewRounds[nextBatch], changedFiles: changed)
        nextBatch += 1
    }
}
