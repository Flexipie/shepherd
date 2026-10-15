import SwiftUI

extension View {
    /// Puts the keyboard in this field when it appears, including when it replaces another field in
    /// a window that is already key. There, setting focus in `onAppear` is too early: the field is
    /// not in the window yet, the old field's editor is gone, and typing goes nowhere.
    func focusOnAppear(_ focused: FocusState<Bool>.Binding) -> some View {
        defaultFocus(focused, true)
            .task {
                await Task.yield()
                focused.wrappedValue = true
            }
    }
}
