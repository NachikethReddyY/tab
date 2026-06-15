//
//  SwitcherView.swift
//  tab
//
//  The switcher UI in Liquid Glass: a separated search card on top, and an
//  app list of individual glass cards below. Rows are fixed-height so the list
//  never shows a half-cut card — when more apps exist than fit, a "more below"
//  chevron appears instead.
//

import SwiftUI

struct SwitcherView: View {
    let viewModel: SwitcherViewModel

    /// Activate the current selection (Return, or "top result" in search mode).
    var onCommit: () -> Void
    /// Dismiss without switching (Escape).
    var onCancel: () -> Void

    @FocusState private var searchFocused: Bool
    @Namespace private var glass

    private var settings: SettingsStore { .shared }

    // Fixed metrics so the list shows only whole rows.
    private let rowHeight: CGFloat = 86
    private let rowSpacing: CGFloat = 10

    private var pitch: CGFloat { rowHeight + rowSpacing }

    /// Dynamically compute how many rows fit between 20% and 80% of the screen.
    private var maxVisibleRows: Int {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return 4 }
        let usableHeight = visible.height * 0.6           // middle 60%
        let headerHeight: CGFloat = 58 + 14 + 14          // search card + top/bottom padding
        let listUsable = usableHeight - headerHeight
        return max(2, Int((listUsable + rowSpacing) / pitch))
    }

    private var maxListHeight: CGFloat { CGFloat(maxVisibleRows) * pitch - rowSpacing }

    /// The list hugs its content up to a whole-row maximum.
    private var listHeight: CGFloat {
        let count = viewModel.filtered.count
        guard count > 0 else { return 0 }
        return min(maxListHeight, CGFloat(count) * pitch - rowSpacing)
    }

    private var hasOverflow: Bool {
        viewModel.filtered.count > maxVisibleRows
    }

    /// Total panel content height (search + list + padding) for the current screen.
    static func idealPanelHeight(for screen: NSScreen?) -> CGFloat {
        guard let visible = screen?.visibleFrame else { return 510 }
        let usable = visible.height * 0.6
        return usable
    }

    private var navAnimation: Animation? {
        settings.animateNavigation ? .snappy(duration: 0.26, extraBounce: 0.06) : nil
    }

    var body: some View {
        VStack(spacing: 24) {
            searchCard
            listContent
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(width: 544, alignment: .top)
        .onChange(of: viewModel.isSearching) { _, searching in
            searchFocused = searching
        }
        .animation(navAnimation, value: viewModel.selectedIndex)
        .animation(navAnimation, value: viewModel.isSearching)
        .animation(navAnimation, value: viewModel.filtered.map(\.id))
    }

    // MARK: Search card (separated, its own glass)

    private var searchCard: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.isSearching ? "magnifyingglass.circle.fill" : "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(viewModel.isSearching ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))

            TextField(
                "",
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.updateSearch($0) }
                ),
                prompt: Text(viewModel.isSearching ? "Search apps…" : "\(settings.searchDescription) to search")
            )
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .regular))
            .focused($searchFocused)
            .onSubmit(onCommit)
            // Arrow keys move the selection while typing: down/right forward, up/left back.
            .onMoveCommand { direction in
                switch direction {
                case .down, .right: viewModel.cycleForward()
                case .up, .left: viewModel.cycleBackward()
                @unknown default: break
                }
            }
            .onExitCommand(perform: onCancel)
        }
        .padding(.horizontal, 22)
        .frame(height: 58)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
    }

    // MARK: List / empty state

    @ViewBuilder
    private var listContent: some View {
        if viewModel.filtered.isEmpty {
            emptyCard
        } else {
            appList
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("No matching apps")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var appList: some View {
        GlassEffectContainer(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: rowSpacing) {
                        ForEach(Array(viewModel.filtered.enumerated()), id: \.element.id) { index, app in
                            AppCard(
                                app: app,
                                isSelected: index == viewModel.selectedIndex,
                                useAccentTint: settings.useAccentTint,
                                height: rowHeight
                            )
                            .id(index)
                            .glassEffectID(app.id, in: glass)
                            .glassEffectTransition(.matchedGeometry)
                            .transition(
                                .asymmetric(
                                    insertion: .push(from: .trailing),
                                    removal: .push(from: .leading)
                                )
                                .combined(with: .opacity)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedIndex = index
                                onCommit()
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: listHeight)
                .onChange(of: viewModel.selectedIndex) { _, index in
                    withAnimation(navAnimation) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
        // "More below" affordance instead of a clipped row.
        .overlay(alignment: .bottom) {
            if hasOverflow {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .offset(y: 14)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }
}

// MARK: - App card

private struct AppCard: View {
    let app: SwitcherWindow
    let isSelected: Bool
    let useAccentTint: Bool
    let height: CGFloat

    private var glassStyle: Glass {
        if isSelected {
            return useAccentTint ? .regular.tint(.accentColor).interactive() : .regular.interactive()
        }
        return .regular
    }

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.dashed").resizable().padding(8)
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.appName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Text(app.displayTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: height)
        .frame(maxWidth: 500)
        .glassEffect(glassStyle, in: .rect(cornerRadius: 18))
        .scaleEffect(isSelected ? 1.0 : 0.975)
    }
}
