import Testing
@testable import ShepherdCore

@Suite struct PaletteModeTests {
    @Test func theListPromptsAPromptableSelectionAndClosesOnEscape() {
        #expect(PaletteMode.list.handle(.tab, canPromptSelection: true, fieldEmpty: false) == .prompt)
        #expect(PaletteMode.list.handle(.right, canPromptSelection: true, fieldEmpty: false) == .prompt)
        // Tab never moves the focus out of the field; right moves the cursor when it cannot prompt.
        #expect(PaletteMode.list.handle(.tab, canPromptSelection: false, fieldEmpty: false) == .swallow)
        #expect(PaletteMode.list.handle(.right, canPromptSelection: false, fieldEmpty: false) == .pass)
        #expect(PaletteMode.list.handle(.left, canPromptSelection: true, fieldEmpty: true) == .pass)
        #expect(PaletteMode.list.handle(.escape, canPromptSelection: true, fieldEmpty: false) == .close)
    }

    @Test func thePromptGoesBackOnEscapeOrLeftInAnEmptyField() {
        #expect(PaletteMode.prompt.handle(.escape, canPromptSelection: false, fieldEmpty: false) == .back)
        #expect(PaletteMode.prompt.handle(.left, canPromptSelection: false, fieldEmpty: true) == .back)
        #expect(PaletteMode.prompt.handle(.left, canPromptSelection: false, fieldEmpty: false) == .pass)
        #expect(PaletteMode.prompt.handle(.right, canPromptSelection: true, fieldEmpty: true) == .pass)
        #expect(PaletteMode.prompt.handle(.tab, canPromptSelection: true, fieldEmpty: true) == .swallow)
    }

    @Test func theFormKeepsItsKeysButEscape() {
        #expect(PaletteMode.newTask.handle(.escape, canPromptSelection: false, fieldEmpty: true) == .back)
        for key in [PaletteMode.Key.tab, .left, .right] {
            #expect(PaletteMode.newTask.handle(key, canPromptSelection: true, fieldEmpty: true) == .pass)
        }
    }
}
