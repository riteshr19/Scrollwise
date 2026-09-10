import Foundation

/// Decodes an array, dropping elements that do not decode instead of failing
/// the whole array.
///
/// Settings are read back from disk, so they are external data: an element
/// written by a newer build, or corrupted, must cost that element and not every
/// setting the user has.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                decoded.append(element)
            } else {
                // A failed decode does not advance the container, so step over
                // the bad element explicitly or this loop never ends.
                _ = try? container.decode(Skip.self)
            }
        }
        elements = decoded
    }

    /// Decodes successfully from any value without reading it.
    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

extension KeyedDecodingContainer {
    /// The value for `key` if it is present and well-formed, otherwise `nil`,
    /// so one bad or missing field falls back to its own default alone.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

extension Array {
    /// Keeps the first element for each key, preserving order.
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
