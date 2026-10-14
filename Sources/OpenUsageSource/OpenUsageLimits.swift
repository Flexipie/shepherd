import Foundation
import ShepherdCore

/// OpenUsage's `openusage.limits.v1` envelope, decoded leniently (only the fields used, unknown
/// ones ignored, a field of the wrong type read as missing), and its mapping to a `UsageReport`.
enum OpenUsageLimits {
    static func report(from data: Data) throws -> UsageReport {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw OpenUsageError.unreadable("not an openusage.limits.v1 answer")
        }
        return report(envelope)
    }

    static func report(_ envelope: Envelope) -> UsageReport {
        var errors: [String: [String]] = [:]
        var problems: [String] = []
        for error in envelope.errors {
            guard let message = error.message else { continue }
            if let id = error.providerId, envelope.providers[id] != nil {
                errors[id, default: []].append(message)
            } else {
                problems.append("OpenUsage: \(message)")
            }
        }
        let providers = envelope.providers
            .map { id, provider in self.provider(id: id, provider, errors: errors[id] ?? []) }
            .sorted(by: order)
        return UsageReport(providers: distinctNames(providers), problems: problems)
    }

    // MARK: Mapping

    static func provider(id: String, _ provider: Provider, errors: [String]) -> UsageProvider {
        let resources = provider.resources.sorted { rank($0.key) == rank($1.key) ? $0.key < $1.key : rank($0.key) < rank($1.key) }
        let meters = resources.compactMap { key, resource in meter(key, resource) }
        let notes = resources.compactMap { key, resource in note(key, resource) } + errors
        let name = provider.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? label(id.components(separatedBy: "@")[0])
        return UsageProvider(id: id, name: name, plan: provider.plan, isStale: provider.stale ?? false, meters: meters,
                             notes: notes, expiresAt: provider.expiresAt.flatMap(date))
    }

    static func meter(_ key: String, _ resource: Resource) -> UsageMeter? {
        guard resource.kind == "consumption" else { return nil }
        let fraction = resource.utilization ?? resource.used.flatMap { used in
            resource.limit.flatMap { $0 > 0 ? used / $0 : nil }
        }
        guard let fraction else { return nil }
        return UsageMeter(id: key, label: label(key), fraction: fraction, valueText: value(resource, fraction: fraction),
                          resetsAt: resource.resetsAt.flatMap(date))
    }

    static func value(_ resource: Resource, fraction: Double) -> String {
        switch (resource.unit, resource.used, resource.limit) {
        case ("percent", let used?, _): "\(Int(used.rounded()))%"
        case ("usd", let used?, let limit?): "\(dollars(used)) of \(dollars(limit))"
        case (let unit?, let used?, let limit?): "\(number(used)) of \(number(limit)) \(unit)"
        default: "\(Int((fraction * 100).rounded()))%"
        }
    }

    /// A balance worth mentioning, as a line. Empty balances are left out.
    static func note(_ key: String, _ resource: Resource) -> String? {
        guard resource.kind == "balance", let available = resource.available, available > 0 else { return nil }
        switch (key, resource.unit) {
        case ("rateLimitResets", _): return available == 1 ? "1 limit reset available" : "\(number(available)) limit resets available"
        case (_, "usd"): return "\(label(key)): \(dollars(available))"
        case (_, let unit?): return "\(label(key)): \(number(available)) \(unit)"
        default: return "\(label(key)): \(number(available))"
        }
    }

    static let knownLabels = ["session": "Session", "weekly": "Weekly", "sonnet": "Sonnet", "opus": "Opus",
                              "fable": "Fable", "extraUsage": "Extra usage"]

    /// Session first, then weekly, then per model, then extra usage, then anything else.
    static func rank(_ key: String) -> Int {
        ["session": 0, "weekly": 1, "opus": 2, "sonnet": 2, "fable": 2, "extraUsage": 3][key] ?? 4
    }

    /// "session" is "Session"; an unknown "someLimit" is "Some limit".
    static func label(_ key: String) -> String {
        if let known = knownLabels[key] { return known }
        var words: [String] = []
        var word = ""
        for character in key {
            if character == "_" || character == "-" || character == " " {
                words.append(word)
                word = ""
            } else if character.isUppercase, !word.isEmpty {
                words.append(word)
                word = String(character)
            } else {
                word.append(character)
            }
        }
        words.append(word)
        let text = words.filter { !$0.isEmpty }.joined(separator: " ").lowercased()
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Claude accounts first (the signed in one, then the others), then the rest by name.
    static func order(_ a: UsageProvider, _ b: UsageProvider) -> Bool {
        func key(_ provider: UsageProvider) -> (Int, String, String) {
            let group = provider.id == "claude" ? 0 : provider.id.hasPrefix("claude@") ? 1 : 2
            return (group, provider.name.lowercased(), provider.id)
        }
        return key(a) < key(b)
    }

    /// Two cards with the same name get their plan (or, failing that, their id) added.
    static func distinctNames(_ providers: [UsageProvider]) -> [UsageProvider] {
        let counts = Dictionary(providers.map { ($0.name, 1) }, uniquingKeysWith: +)
        return providers.map { provider in
            guard counts[provider.name, default: 0] > 1 else { return provider }
            let suffix = provider.plan ?? provider.id
            return UsageProvider(id: provider.id, name: "\(provider.name) (\(suffix))", plan: provider.plan, isStale: provider.isStale,
                                 meters: provider.meters, notes: provider.notes, expiresAt: provider.expiresAt)
        }
    }

    static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: .iso8601))
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    static func dollars(_ value: Double) -> String {
        value >= 10 || value.rounded() == value ? "$\(Int(value.rounded()))" : String(format: "$%.2f", value)
    }

    // MARK: Wire

    struct Envelope: Decodable {
        let providers: [String: Provider]
        let errors: [ProviderError]

        enum CodingKeys: String, CodingKey { case providers, errors }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let providers = try container.decode([String: Lenient<Provider>].self, forKey: .providers)
            self.providers = providers.compactMapValues(\.value)
            errors = (try? container.decodeIfPresent([Lenient<ProviderError>].self, forKey: .errors))?.compactMap(\.value) ?? []
        }
    }

    struct Provider: Decodable {
        let displayName: String?
        let plan: String?
        let stale: Bool?
        let expiresAt: String?
        let resources: [String: Resource]

        enum CodingKeys: String, CodingKey { case displayName, plan, stale, expiresAt, resources }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            displayName = try? container.decodeIfPresent(String.self, forKey: .displayName)
            plan = try? container.decodeIfPresent(String.self, forKey: .plan)
            stale = try? container.decodeIfPresent(Bool.self, forKey: .stale)
            expiresAt = try? container.decodeIfPresent(String.self, forKey: .expiresAt)
            let resources = try? container.decodeIfPresent([String: Lenient<Resource>].self, forKey: .resources)
            self.resources = resources?.compactMapValues(\.value) ?? [:]
        }
    }

    struct Resource: Decodable {
        let kind: String?
        let unit: String?
        let used: Double?
        let limit: Double?
        let utilization: Double?
        let available: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey { case kind, unit, used, limit, utilization, available, resetsAt }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try? container.decodeIfPresent(String.self, forKey: .kind)
            unit = try? container.decodeIfPresent(String.self, forKey: .unit)
            used = try? container.decodeIfPresent(Double.self, forKey: .used)
            limit = try? container.decodeIfPresent(Double.self, forKey: .limit)
            utilization = try? container.decodeIfPresent(Double.self, forKey: .utilization)
            available = try? container.decodeIfPresent(Double.self, forKey: .available)
            resetsAt = try? container.decodeIfPresent(String.self, forKey: .resetsAt)
        }
    }

    struct ProviderError: Decodable {
        let providerId: String?
        let message: String?
    }

    /// A value that is nil instead of failing the whole answer when it does not decode.
    struct Lenient<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }
}
