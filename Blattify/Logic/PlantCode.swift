import Foundation

/// A plant code in the canonical format `XX-XX`.
///
/// Uses an alphabet without easily confused characters (no `I`, `L`, `O`, `0`, `1`),
/// giving 31 symbols and 923,521 possible codes.
nonisolated struct PlantCode: Hashable, Sendable, CustomStringConvertible {
    enum GenerationError: Error {
        /// No unused code was found within the allowed number of attempts.
        case exhausted
    }

    static let alphabet: [Character] = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let urlScheme = "blattify"
    static let urlHost = "plant"

    private static let allowedCharacters = Set(alphabet)

    /// Canonical form, e.g. `AB-23`.
    let rawValue: String

    var description: String { rawValue }

    /// Deep link encoded in the QR label, e.g. `blattify://plant/AB-23`.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = Self.urlHost
        components.path = "/" + rawValue
        // Force unwrap avoided: the components above always form a valid URL.
        return components.url ?? URL(fileURLWithPath: rawValue)
    }

    /// Creates a code from user input (case-insensitive, dash and spaces optional).
    init?(_ input: String) {
        guard let normalized = Self.normalize(input) else { return nil }
        rawValue = normalized
    }

    /// Creates a code from a scanned QR payload: either a `blattify://plant/XX-XX` URL or a plain code.
    init?(payload: String) {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            self.init(url: url)
        } else {
            self.init(trimmed)
        }
    }

    /// Creates a code from a `blattify://plant/XX-XX` deep link.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme,
              url.host()?.lowercased() == Self.urlHost,
              let last = url.pathComponents.last(where: { $0 != "/" }) else { return nil }
        self.init(last)
    }

    private init(validated: String) {
        rawValue = validated
    }

    /// Normalizes user input to `XX-XX`: trims, uppercases, removes dashes and spaces,
    /// and validates length and alphabet. Returns `nil` for invalid input.
    static func normalize(_ input: String) -> String? {
        let compact = input
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "-" }
        guard compact.count == 4, compact.allSatisfy(allowedCharacters.contains) else { return nil }
        return "\(compact.prefix(2))-\(compact.suffix(2))"
    }

    /// Formats partial input while the user types: uppercases, drops characters outside the alphabet,
    /// keeps at most 4 symbols and inserts the dash after the second one (`ab2` → `AB-2`).
    /// A dash typed (or left after deleting) right after two symbols is kept (`ab-` → `AB-`),
    /// so backspacing across the dash does not trigger a reformat.
    /// `hadInvalidCharacters` reports whether anything other than dashes or spaces was dropped.
    static func formatPartialInput(_ input: String) -> (text: String, hadInvalidCharacters: Bool) {
        var hadInvalidCharacters = false
        var symbols: [Character] = []
        for character in input.uppercased() where character != "-" && !character.isWhitespace {
            if allowedCharacters.contains(character) {
                if symbols.count < 4 {
                    symbols.append(character)
                }
            } else {
                hadInvalidCharacters = true
            }
        }
        var text = String(symbols.prefix(2))
        if symbols.count > 2 {
            text += "-" + String(symbols.dropFirst(2))
        } else if symbols.count == 2, input.trimmingCharacters(in: .whitespaces).hasSuffix("-") {
            text += "-"
        }
        return (text, hadInvalidCharacters)
    }

    /// `true` only for strings already in canonical `XX-XX` form.
    static func isValid(_ string: String) -> Bool {
        normalize(string) == string
    }

    /// A random code (not checked for uniqueness).
    static func random<G: RandomNumberGenerator>(using generator: inout G) -> PlantCode {
        // Modulo bias is negligible for 31 symbols over a 64-bit range.
        let characters = (0..<4).map { _ in
            alphabet[Int(generator.next() % UInt64(alphabet.count))]
        }
        let string = String(characters)
        return PlantCode(validated: "\(string.prefix(2))-\(string.suffix(2))")
    }

    /// A random code that is not contained in `usedCodes`.
    static func generate<G: RandomNumberGenerator>(
        excluding usedCodes: Set<String>,
        maxAttempts: Int = 10_000,
        using generator: inout G
    ) throws(GenerationError) -> PlantCode {
        for _ in 0..<maxAttempts {
            let candidate = random(using: &generator)
            if !usedCodes.contains(candidate.rawValue) {
                return candidate
            }
        }
        throw .exhausted
    }

    static func generate(excluding usedCodes: Set<String>) throws(GenerationError) -> PlantCode {
        var generator = SystemRandomNumberGenerator()
        return try generate(excluding: usedCodes, using: &generator)
    }
}
