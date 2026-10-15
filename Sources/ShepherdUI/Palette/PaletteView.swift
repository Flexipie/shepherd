import ShepherdCore
import SwiftUI

/// What the palette can find, computed by the app from the store and the modules.
public struct PaletteContent: Sendable, Equatable {
    public var items: [PaletteItem]
    /// Why the list may be short or empty, such as "Not connected: …"; nil while live.
    public var notice: String?

    public init(items: [PaletteItem], notice: String? = nil) {
        self.items = items
        self.notice = notice
    }
}

/// The palette: a search field over every agent, project and command. Typing filters, up and
/// down move the selection, Return chooses it, hovering selects and clicking chooses.
public struct PaletteView: View {
    let content: PaletteContent
    let clock: PanelClock
    let maxListHeight: CGFloat?
    let perform: (PaletteAction) -> Void

    @State private var query: String
    @State private var selection: PaletteItem.ID?
    @State private var listHeight: CGFloat = 0
    /// Where the mouse last was over a row, so rows moving under a still mouse do not select.
    @State private var mouse: CGPoint?
    @FocusState private var fieldFocused: Bool

    public nonisolated static let width: CGFloat = 640

    /// `maxListHeight` makes the results scroll past that height; nil lets the view grow.
    public init(content: PaletteContent, clock: PanelClock = .live, maxListHeight: CGFloat? = nil, query: String = "",
                selection: PaletteItem.ID? = nil, perform: @escaping (PaletteAction) -> Void) {
        self.content = content
        self.clock = clock
        self.maxListHeight = maxListHeight
        self.perform = perform
        _query = State(initialValue: query)
        _selection = State(initialValue: selection)
    }

    public var body: some View {
        Group {
            switch clock {
            case .live: TimelineView(.everyMinute) { context in palette(now: context.date) }
            case .fixed(let date): palette(now: date)
            }
        }
        .frame(width: Self.width)
    }

    private var results: [PaletteResult] {
        PaletteSearch.results(content.items, query: query)
    }

    /// The selection if it is still among the results, else the first result.
    private func selected(in results: [PaletteResult]) -> PaletteItem.ID? {
        results.contains { $0.id == selection } ? selection : results.first?.id
    }

    private func palette(now: Date) -> some View {
        let results = results
        let selected = selected(in: results)
        return VStack(alignment: .leading, spacing: 0) {
            field(results)
            Divider().padding(.horizontal, 10)
            if results.isEmpty {
                Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? "Nothing to show yet" : "No matches")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            } else if let maxListHeight {
                ScrollViewReader { proxy in
                    ScrollView {
                        list(results, selected: selected, now: now)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(listHeight, maxListHeight))
                    .onChange(of: selected) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            } else {
                list(results, selected: selected, now: now)
            }
            footer
        }
    }

    private func field(_ results: [PaletteResult]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Jump to an agent, project or command", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($fieldFocused)
                .onSubmit { choose(selected(in: results), in: results) }
                .onKeyPress(.downArrow) { move(1, in: results) }
                .onKeyPress(.upArrow) { move(-1, in: results) }
                .onChange(of: query) { selection = nil }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .onAppear { fieldFocused = true }
    }

    private func list(_ results: [PaletteResult], selected: PaletteItem.ID?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(results) { result in
                PaletteRow(result: result, now: now, isSelected: result.id == selected)
                    .onContinuousHover(coordinateSpace: .global) { phase in
                        guard case .active(let location) = phase, location != mouse else { return }
                        if mouse != nil { selection = result.id }
                        mouse = location
                    }
                    .onTapGesture { choose(result.id, in: results) }
                    .id(result.id)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let notice = content.notice {
                Text(notice).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text("↩ jump · esc close")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().padding(.horizontal, 10) }
    }

    private func move(_ offset: Int, in results: [PaletteResult]) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        let index = results.firstIndex { $0.id == selected(in: results) } ?? 0
        selection = results[min(max(index + offset, 0), results.count - 1)].id
        return .handled
    }

    private func choose(_ id: PaletteItem.ID?, in results: [PaletteResult]) {
        guard let action = results.first(where: { $0.id == id })?.item.action else { return }
        perform(action)
    }
}
