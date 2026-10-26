import ShepherdCore
import SwiftUI

/// The plugin actions for one agent or project, opened with ⌘K.
public struct PluginActionsPage: Sendable, Equatable {
    /// The agent's or project's name.
    public let title: String
    /// Each action as a palette command.
    public let items: [PaletteItem]

    public init(title: String, items: [PaletteItem]) {
        self.title = title
        self.items = items
    }
}

/// A plugin action running, or what it printed, or why it failed.
public struct PluginResultPage: Sendable, Equatable {
    public let title: String
    public let isRunning: Bool
    public let text: String?
    public let error: String?

    public init(title: String, isRunning: Bool = false, text: String? = nil, error: String? = nil) {
        self.title = title
        self.isRunning = isRunning
        self.text = text
        self.error = error
    }
}

/// The ⌘K page: a field that filters the actions, then the list. Up and down move, Return runs,
/// Left in an empty field or Escape goes back.
struct PaletteActionsPageView: View {
    let page: PluginActionsPage
    let now: Date
    let maxListHeight: CGFloat?
    let onEvent: (PaletteEvent) -> Void

    @State private var query = ""
    @State private var selection: PaletteItem.ID?
    @FocusState private var focused: Bool

    var body: some View {
        let results = PaletteSearch.results(page.items, query: query)
        let selected = results.contains { $0.id == selection } ? selection : results.first?.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bolt")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Actions for \(page.title)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($focused)
                    .onSubmit { run(selected, in: results) }
                    .onKeyPress(.downArrow) { move(1, from: selected, in: results) }
                    .onKeyPress(.upArrow) { move(-1, from: selected, in: results) }
                    .onKeyPress(.leftArrow) { query.isEmpty ? back() : .ignored }
                    .onChange(of: query) { selection = nil }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .focusOnAppear($focused)
            Divider().padding(.horizontal, 10)
            if results.isEmpty {
                Text(page.items.isEmpty ? "No plugin actions for \(page.title). A plugin adds them; see the README." : "No matches")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { result in
                        PaletteRow(result: result, now: now, isSelected: result.id == selected)
                            .onTapGesture { run(result.id, in: results) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxHeight: maxListHeight)
            }
        }
    }

    private func move(_ offset: Int, from selected: PaletteItem.ID?, in results: [PaletteResult]) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        let index = results.firstIndex { $0.id == selected } ?? 0
        selection = results[min(max(index + offset, 0), results.count - 1)].id
        return .handled
    }

    private func run(_ id: PaletteItem.ID?, in results: [PaletteResult]) {
        guard let action = results.first(where: { $0.id == id })?.item.action else { return }
        onEvent(.perform(action))
    }

    private func back() -> KeyPress.Result {
        onEvent(.back)
        return .handled
    }
}

/// What a plugin action printed, selectable, or why it failed. Escape goes back.
struct PaletteResultPageView: View {
    let page: PluginResultPage
    let maxHeight: CGFloat?

    @State private var textHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if page.isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: page.error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(page.error == nil ? Color.green : Color.orange)
                }
                Text(page.isRunning ? "Running \(page.title)…" : page.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            if let error = page.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let text = page.text {
                let body = Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let maxHeight {
                    ScrollView {
                        body.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(textHeight, maxHeight))
                } else {
                    body
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
