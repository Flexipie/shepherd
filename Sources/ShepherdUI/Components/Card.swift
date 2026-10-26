import SwiftUI

extension View {
    /// The rounded fill behind every card: a project, a repo, a gadget. `padding` is the room
    /// between the fill and the content.
    func card(padding: EdgeInsets = EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)) -> some View {
        self.padding(padding).background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045)))
    }
}
