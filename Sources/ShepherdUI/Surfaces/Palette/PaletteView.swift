import ShepherdCore
import SwiftUI

/// What the palette shows, computed by the app from the store, the modules and its stage.
public struct PaletteContent: Sendable, Equatable {
    public var items: [PaletteItem]
    /// Why the list may be short or empty, such as "Not connected: …", or that something is wrong
    /// and where to read about it; nil while all is well.
    public var notice: String?
    /// The notice is about problems, so it shows a warning.
    public var noticeIsProblem: Bool
    /// The first-run guide, shown above the commands while nothing is typed; nil once agents or projects show.
    public var guide: PanelSection?
    public var page: PalettePage

    public init(items: [PaletteItem], notice: String? = nil, noticeIsProblem: Bool = false, guide: PanelSection? = nil,
                page: PalettePage = .list) {
        self.items = items
        self.notice = notice
        self.noticeIsProblem = noticeIsProblem
        self.guide = guide
        self.page = page
    }
}

/// The palette's page: the list, a prompt for one agent, the new task form, an agent's or
/// project's plugin actions, a plugin action's result, the plugins' gadgets, or the status page.
public enum PalettePage: Sendable, Equatable {
    case list
    case prompt(AgentStage)
    case newTask(NewTaskStage)
    case actions(PluginActionsPage)
    case result(PluginResultPage)
    case gadgets([GadgetCard])
    case status(PaletteStatusPage)

    public var mode: PaletteMode {
        switch self {
        case .list: .list
        case .prompt: .prompt
        case .newTask: .newTask
        case .actions: .actions
        case .result: .result
        case .gadgets: .gadgets
        case .status: .status
        }
    }
}

/// What the palette asks the app to do.
public enum PaletteEvent: Sendable, Equatable {
    /// The list's selection was chosen.
    case perform(PaletteAction)
    /// Prompt this agent.
    case prompt(AgentID)
    /// Show the plugin actions for this agent or project.
    case actions(PluginTarget)
    /// Back to the list.
    case back
    /// Send to the prompted agent, or start the task.
    case stage(StageAction)
}

/// The palette: a search field over every agent, project and command. Typing filters, up and
/// down move the selection, Return chooses it, Tab (or right) prompts the selected agent, ⌘K
/// shows the selected agent's or project's plugin actions, hovering selects and clicking chooses.
/// The query is kept while another page shows.
public struct PaletteView: View {
    let content: PaletteContent
    let clock: PanelClock
    let maxListHeight: CGFloat?
    let onEvent: (PaletteEvent) -> Void

    @State private var query: String
    @State private var selection: PaletteItem.ID?
    @State private var draft: String
    @State private var listHeight: CGFloat = 0
    /// Where the mouse last was over a row, so rows moving under a still mouse do not select.
    @State private var mouse: CGPoint?
    @FocusState private var fieldFocused: Bool

    public nonisolated static let width: CGFloat = 640

    /// `maxListHeight` makes the results scroll past that height; nil lets the view grow.
    public init(content: PaletteContent, clock: PanelClock = .live, maxListHeight: CGFloat? = nil, query: String = "",
                selection: PaletteItem.ID? = nil, draft: String = "", onEvent: @escaping (PaletteEvent) -> Void) {
        self.content = content
        self.clock = clock
        self.maxListHeight = maxListHeight
        self.onEvent = onEvent
        _query = State(initialValue: query)
        _selection = State(initialValue: selection)
        _draft = State(initialValue: draft)
    }

    public var body: some View {
        Clocked(clock: clock) { now in page(now: now) }
        .frame(width: Self.width)
    }

    private func page(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch content.page {
            case .list: palette(now: now)
            case .prompt(let stage):
                PalettePromptPage(stage: stage, now: now, maxHeight: maxListHeight, draft: $draft) { event in
                    if event == .back { draft = "" }
                    onEvent(event)
                }
            case .newTask(let stage):
                NewTaskView(stage: stage) { action in onEvent(action == .close ? .back : .stage(action)) }
                    .padding(16)
            case .actions(let page):
                PaletteActionsPageView(page: page, now: now, maxListHeight: maxListHeight, onEvent: onEvent)
            case .result(let page):
                PaletteResultPageView(page: page, maxHeight: maxListHeight)
            case .gadgets(let cards):
                PaletteGadgetsPageView(cards: cards, now: now, maxHeight: maxListHeight)
            case .status(let page):
                PaletteStatusPageView(page: page, now: now, maxHeight: maxListHeight)
            }
            footer
        }
    }

    private var results: [PaletteResult] {
        PaletteSearch.results(content.items, query: query)
    }

    private var showsGuide: Bool {
        content.guide != nil && query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The selection if it is still among the results, else the first result. While the first-run
    /// guide shows, nothing until an arrow picks a row, so Return never runs a command it pushed
    /// out of view.
    private func selected(in results: [PaletteResult]) -> PaletteItem.ID? {
        if results.contains(where: { $0.id == selection }) { return selection }
        return showsGuide ? nil : results.first?.id
    }

    private func palette(now: Date) -> some View {
        let results = results
        let selected = selected(in: results)
        return VStack(alignment: .leading, spacing: 0) {
            field(results, selected: selected)
            Divider().padding(.horizontal, 10)
            if results.isEmpty && !showsGuide {
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
        }
    }

    private func field(_ results: [PaletteResult], selected: PaletteItem.ID?) -> some View {
        let selectedItem = results.first { $0.id == selected }?.item
        let promptable = selectedItem.flatMap { item -> AgentID? in
            guard item.canPrompt, case .agent(let row) = item.kind else { return nil }
            return row.agent.id
        }
        let target: PluginTarget? = switch selectedItem?.kind {
        case .agent(let row)?: .agent(row.agent.id)
        case .project(let project, _, _)?: .project(project.id)
        default: nil
        }
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Jump to an agent, project or command", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($fieldFocused)
                // Read the selection when Return is pressed, as the arrows do: the field can keep an
                // older onSubmit, whose captured selection would be the first row (#86).
                .onSubmit { choose(self.selected(in: results), in: results) }
                .onKeyPress(.downArrow) { move(1, in: results) }
                .onKeyPress(.upArrow) { move(-1, in: results) }
                .onKeyPress(.tab) { key(.tab, prompting: promptable) }
                .onKeyPress(.rightArrow) { key(.right, prompting: promptable) }
                .onChange(of: query) { selection = nil }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .focusOnAppear($fieldFocused)
        .background {
            // ⌘K, as a shortcut so the text field does not take it first.
            Button("Actions") { if let target { onEvent(.actions(target)) } }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    /// The rows, under the first-run guide while it shows.
    private func list(_ results: [PaletteResult], selected: PaletteItem.ID?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsGuide, let guide = content.guide {
                PaletteGuideView(guide: guide, now: now)
            }
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
                HStack(spacing: 4) {
                    if content.noticeIsProblem {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Text(notice).lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            Text(hint)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().padding(.horizontal, 10) }
    }

    private var hint: String {
        switch content.page {
        case .list: showsGuide ? "↓ commands · esc close" : "↩ jump · ⇥ prompt · ⌘K actions · esc close"
        case .prompt(let stage):
            [stage.canReply ? (stage.prompts ? "↩ prompt" : "↩ reply") : nil,
             stage.canSendKeys && !stage.choices.isEmpty ? "⌘digit choose" : nil, "esc back"]
                .compactMap { $0 }.joined(separator: " · ")
        case .newTask: "esc back"
        case .actions: "↩ run · esc back"
        case .result, .gadgets, .status: "esc back"
        }
    }

    private func key(_ key: PaletteMode.Key, prompting agent: AgentID?) -> KeyPress.Result {
        switch PaletteMode.list.handle(key, canPromptSelection: agent != nil, fieldEmpty: query.isEmpty) {
        case .prompt:
            guard let agent else { return .ignored }
            draft = ""
            onEvent(.prompt(agent))
            return .handled
        case .swallow: return .handled
        case .back, .close, .pass: return .ignored
        }
    }

    private func move(_ offset: Int, in results: [PaletteResult]) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        // From no selection (under the guide) either arrow picks the first row.
        let index = results.firstIndex { $0.id == selected(in: results) }.map { $0 + offset } ?? 0
        selection = results[min(max(index, 0), results.count - 1)].id
        return .handled
    }

    private func choose(_ id: PaletteItem.ID?, in results: [PaletteResult]) {
        guard let action = results.first(where: { $0.id == id })?.item.action else { return }
        onEvent(.perform(action))
    }
}
