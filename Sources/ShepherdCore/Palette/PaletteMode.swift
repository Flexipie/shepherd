/// Which page the palette shows, and what its keys do there. Typing, up, down and Return belong
/// to each page's field; these are the keys that move between pages.
public enum PaletteMode: Sendable, Equatable {
    /// The search field and its results.
    case list
    /// A prompt for one agent.
    case prompt
    /// The new task form.
    case newTask
    /// The plugin actions for one agent or project (⌘K).
    case actions
    /// What a plugin action printed, or why it failed.
    case result

    public enum Key: Sendable {
        case tab, right, left, escape
    }

    public enum Outcome: Sendable, Equatable {
        /// Prompt the selected agent.
        case prompt
        /// Back to the list, with the query kept.
        case back
        case close
        /// Handled, nothing changes, so the key does not move the focus.
        case swallow
        /// Not the palette's: the field gets the key (the cursor moves).
        case pass
    }

    /// - Parameters:
    ///   - canPromptSelection: the list's selection is an agent that can take a prompt or reply.
    ///   - fieldEmpty: the current page's field is empty.
    public func handle(_ key: Key, canPromptSelection: Bool, fieldEmpty: Bool) -> Outcome {
        switch (self, key) {
        case (.list, .tab): canPromptSelection ? .prompt : .swallow
        case (.list, .right): canPromptSelection ? .prompt : .pass
        case (.list, .left): .pass
        case (.list, .escape): .close
        case (.prompt, .left): fieldEmpty ? .back : .pass
        case (.prompt, .right): .pass
        case (.prompt, .tab): .swallow
        case (.prompt, .escape), (.newTask, .escape), (.actions, .escape), (.result, .escape): .back
        case (.actions, .left): fieldEmpty ? .back : .pass
        case (.actions, .tab), (.result, .tab): .swallow
        case (.actions, _), (.result, _): .pass
        // The form's own fields take Tab and the arrows.
        case (.newTask, _): .pass
        }
    }
}
