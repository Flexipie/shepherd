import Foundation

/// An agent's context size in words: "184k" on a row, "184,213 tokens" in help, "184 thousand
/// tokens" spoken.
enum ContextSize {
    static func short(_ tokens: Int) -> String {
        switch tokens {
        case ..<1000: "\(tokens)"
        case ..<999_500: "\(Int((Double(tokens) / 1000).rounded()))k"
        default: String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
    }

    static func help(_ tokens: Int) -> String {
        "Context: \(tokens.formatted(.number)) tokens"
    }

    static func spoken(_ tokens: Int) -> String {
        switch tokens {
        case ..<1000: "context \(tokens) tokens"
        case ..<999_500: "context \(Int((Double(tokens) / 1000).rounded())) thousand tokens"
        default: "context \(String(format: "%.1f", Double(tokens) / 1_000_000)) million tokens"
        }
    }
}
