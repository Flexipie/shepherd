import ShepherdCore
import SwiftUI
import Testing
@testable import ShepherdUI

@MainActor
@Suite struct PaletteGadgetsSnapshotTests {
    /// The Gadgets command's page, for Macs without a notch.
    @Test func gadgetsPage() throws {
        try Snapshot.check("palette-gadgets", width: PaletteView.width) {
            PaletteView(content: PaletteContent(items: [], page: .gadgets(SampleHerd.pluginGadgetCards)),
                        clock: .fixed(SampleHerd.now)) { _ in }
        }
    }
}
