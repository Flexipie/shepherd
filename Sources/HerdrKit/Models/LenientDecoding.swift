import Foundation

// herdr adds fields between releases and leaves out empty ones, so decoding is lenient:
// unknown keys are ignored, optional and collection fields default when missing or malformed,
// and one malformed element does not sink a whole array.

extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ key: Key, default value: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? value
    }

    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Decodes an array, dropping elements that fail to decode.
    func lossyArray<T: Decodable>(_ key: Key) -> [T] {
        (lenient(key, default: LossyArray<T>(elements: []))).elements
    }
}

private struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(elements: [Element]) {
        self.elements = elements
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        self.elements = elements
    }

    private struct Skip: Decodable {}
}
