/// A tiny, dependency-free glob matcher for repo-relative paths.
///
/// `**` matches zero or more whole path segments, `*` matches within one segment,
/// `?` matches one character within a segment. Matching is case-sensitive, like Git.
public struct Glob: Sendable, Equatable, Hashable {
    public let pattern: String
    private let segments: [String]

    public init(_ pattern: String) {
        self.pattern = pattern
        self.segments = pattern.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    public func matches(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return Self.match(segments[...], parts[...])
    }

    private static func match(_ pattern: ArraySlice<String>, _ path: ArraySlice<String>) -> Bool {
        guard let head = pattern.first else { return path.isEmpty }
        if head == "**" {
            // Zero segments, or consume one path segment and try again.
            if match(pattern.dropFirst(), path) { return true }
            guard !path.isEmpty else { return false }
            return match(pattern, path.dropFirst())
        }
        guard let segment = path.first, matchSegment(Array(head), Array(segment)) else { return false }
        return match(pattern.dropFirst(), path.dropFirst())
    }

    /// Iterative wildcard match with single-star backtracking: linear in practice, no recursion.
    private static func matchSegment(_ p: [Character], _ s: [Character]) -> Bool {
        var pi = 0, si = 0
        var starIndex: Int? = nil
        var matchIndex = 0
        while si < s.count {
            if pi < p.count, p[pi] == "?" || p[pi] == s[si] {
                pi += 1
                si += 1
            } else if pi < p.count, p[pi] == "*" {
                starIndex = pi
                matchIndex = si
                pi += 1
            } else if let star = starIndex {
                pi = star + 1
                matchIndex += 1
                si = matchIndex
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
