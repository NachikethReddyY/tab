//
//  FuzzySearch.swift
//  tab
//
//  Subsequence fuzzy matching with a relevance score, used to rank windows.
//

import Foundation

enum FuzzySearch {

    /// Scores `query` against `target`. Returns `nil` when the query characters
    /// don't all appear, in order, inside the target (i.e. no match at all).
    ///
    /// Higher is better. Exact and prefix matches get large baseline bonuses;
    /// otherwise the score rewards consecutive runs and word-boundary hits and
    /// lightly penalises long targets so tighter matches win.
    static func score(query: String, target: String) -> Int? {
        if query.isEmpty { return 0 }

        let lowerQuery = query.lowercased()
        let lowerTarget = target.lowercased()
        if lowerTarget.isEmpty { return nil }

        if lowerTarget == lowerQuery { return 10_000 }
        if lowerTarget.hasPrefix(lowerQuery) { return 5_000 }

        let q = Array(lowerQuery)
        let t = Array(lowerTarget)

        var score = 0
        var qi = 0
        var previousMatch = -2

        for ti in t.indices {
            guard qi < q.count, t[ti] == q[qi] else { continue }

            score += 10
            if ti == previousMatch + 1 {
                score += 15 // consecutive characters
            }
            let isBoundary = ti == 0 || t[ti - 1] == " " || t[ti - 1] == "-" || t[ti - 1] == "_"
            if isBoundary {
                score += 20 // start of a word
            }
            previousMatch = ti
            qi += 1
        }

        // Every query character must have been matched, in order.
        guard qi == q.count else { return nil }

        score -= t.count / 10
        return score
    }
}
