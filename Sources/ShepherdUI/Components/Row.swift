import AppKit
import ShepherdCore
import SwiftUI

extension View {
    /// The padding and selection highlight every row shares, in the panel, the notch bar and the
    /// palette. The whole row takes clicks.
    func rowChrome(isSelected: Bool, vertical: CGFloat) -> some View {
        padding(.horizontal, 8)
            .padding(.vertical, vertical)
            .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Color.accentColor.opacity(0.18) : .clear))
            .contentShape(Rectangle())
    }

    /// Makes a row choosable within its section: a click performs `action` (⌘-click jumps when
    /// the surface offers it), hovering selects it, and its id lets a surface scroll to it.
    func choosable(_ action: PanelAction?, in rows: RowContext) -> some View {
        let id = rows.id(action)
        return onTapGesture { if let action { tap(action, perform: rows.perform, jump: rows.jump) } }
            .onHover { inside in if inside, let id { rows.select(id) } }
            .id(id)
    }
}

/// What a section's rows need from the surface that shows them: which section they are in, what
/// is selected, and what choosing and hovering do. With `jump`, agent rows show a jump arrow and
/// ⌘-click jumps instead of `perform`.
struct RowContext {
    let sectionID: String
    let selection: PanelTarget.ID?
    var jump: ((PanelAction) -> Void)?
    let perform: (PanelAction) -> Void
    let select: (PanelTarget.ID) -> Void

    func id(_ action: PanelAction?) -> PanelTarget.ID? {
        action.map { PanelTarget.id(section: sectionID, action: $0) }
    }

    func isSelected(_ action: PanelAction?) -> Bool {
        id(action).map { $0 == selection } ?? false
    }

    /// The jump arrow's action for a row, when the surface offers jumping and the row can.
    func onJump(_ action: PanelAction?) -> (() -> Void)? {
        guard let jump, let action else { return nil }
        return { jump(action) }
    }

    /// The same rows without the jump arrow, for a header that only performs.
    var withoutJump: RowContext {
        RowContext(sectionID: sectionID, selection: selection, jump: nil, perform: perform, select: select)
    }
}

/// A click on a row: ⌘-click jumps when the row offers it, a plain click performs.
@MainActor
func tap(_ action: PanelAction, perform: (PanelAction) -> Void, jump: ((PanelAction) -> Void)?) {
    if let jump, NSEvent.modifierFlags.contains(.command) {
        jump(action)
    } else {
        perform(action)
    }
}
