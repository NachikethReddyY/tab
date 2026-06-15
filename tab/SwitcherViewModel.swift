//
//  SwitcherViewModel.swift
//  tab
//
//  Drives the switcher's state machine: the frozen window snapshot, the live
//  filtered/ranked list, the current selection, and whether search is active.
//

import Foundation
import Observation

@MainActor
@Observable
final class SwitcherViewModel {

    /// The full snapshot taken when the switcher opened. Frozen until it closes
    /// so typing never triggers fresh (and laggy) system queries.
    private(set) var windows: [SwitcherWindow] = []

    /// The list actually shown: `windows` when idle, or the ranked matches.
    private(set) var filtered: [SwitcherWindow] = []

    var selectedIndex: Int = 0
    var searchText: String = ""
    private(set) var isSearching: Bool = false

    var selectedWindow: SwitcherWindow? {
        filtered.indices.contains(selectedIndex) ? filtered[selectedIndex] : nil
    }

    /// Resets state for a freshly opened switcher.
    func begin(with windows: [SwitcherWindow]) {
        self.windows = windows
        searchText = ""
        isSearching = false
        applyFilter()
        // Mirror Cmd+Tab: pre-select the *next* window, not the current one.
        selectedIndex = filtered.count > 1 ? 1 : 0
    }

    func cycleForward() {
        guard !filtered.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % filtered.count
    }

    func cycleBackward() {
        guard !filtered.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + filtered.count) % filtered.count
    }

    func enterSearch() {
        guard !isSearching else { return }
        isSearching = true
    }

    func reset() {
        isSearching = false
        searchText = ""
        windows = []
        filtered = []
        selectedIndex = 0
    }

    /// Called as the user types; re-ranks and clamps the selection.
    func updateSearch(_ text: String) {
        guard isSearching else { return }
        searchText = text
        applyFilter()
        selectedIndex = 0
    }

    private func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            filtered = windows
            clampSelection()
            return
        }

        filtered = windows
            .compactMap { window -> (window: SwitcherWindow, score: Int)? in
                guard let score = FuzzySearch.score(query: query, target: window.searchableText) else {
                    return nil
                }
                return (window, score)
            }
            .sorted { $0.score > $1.score }
            .map(\.window)

        clampSelection()
    }

    /// Guarantees `selectedIndex` is always a valid row (or 0 when empty),
    /// preventing out-of-bounds access after the list shrinks.
    private func clampSelection() {
        if filtered.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= filtered.count {
            selectedIndex = filtered.count - 1
        } else if selectedIndex < 0 {
            selectedIndex = 0
        }
    }
}
