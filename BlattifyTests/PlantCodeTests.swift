import Foundation
import Testing
@testable import Blattify

/// Deterministic random number generator (SplitMix64) for reproducible tests.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Always returns the same value, so every generated code is identical.
private struct ConstantGenerator: RandomNumberGenerator {
    mutating func next() -> UInt64 { 0 }
}

struct PlantCodeTests {
    @Test func alphabetExcludesAmbiguousCharacters() {
        let alphabet = PlantCode.alphabet
        #expect(alphabet.count == 31)
        #expect(Set(alphabet).count == alphabet.count)
        for ambiguous in "ILO01" {
            #expect(!alphabet.contains(ambiguous))
        }
    }

    @Test func generatedCodesHaveCanonicalFormat() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<1_000 {
            let code = PlantCode.random(using: &generator)
            #expect(PlantCode.isValid(code.rawValue))
            #expect(code.rawValue.count == 5)
        }
    }

    @Test(arguments: [
        ("AB-CD", "AB-CD"),
        ("ab-cd", "AB-CD"),
        ("abcd", "AB-CD"),
        ("  aB cD \n", "AB-CD"),
        ("k7-3x", "K7-3X"),
        ("a-b-c-d", "AB-CD"),
    ])
    func normalizeAcceptsValidInput(input: String, expected: String) {
        #expect(PlantCode.normalize(input) == expected)
        #expect(PlantCode(input)?.rawValue == expected)
    }

    @Test(arguments: ["", "ABC", "ABCDE", "AB-C", "AB-1C", "AO-CD", "IL-AB", "A0-BC", "AB_CD", "ÄB-CD"])
    func normalizeRejectsInvalidInput(input: String) {
        #expect(PlantCode.normalize(input) == nil)
        #expect(PlantCode(input) == nil)
    }

    @Test(arguments: [
        ("", "", false),
        ("a", "A", false),
        ("ab", "AB", false),
        ("ab-", "AB-", false),
        ("a-", "A", false),
        ("ab2", "AB-2", false),
        ("ab23", "AB-23", false),
        ("ab234", "AB-23", false),
        ("a1b", "AB", true),
        ("o", "", true),
    ])
    func formatPartialInput(input: String, expectedText: String, expectedInvalid: Bool) {
        let result = PlantCode.formatPartialInput(input)
        #expect(result.text == expectedText)
        #expect(result.hadInvalidCharacters == expectedInvalid)
    }

    @Test func isValidRequiresCanonicalForm() {
        #expect(PlantCode.isValid("AB-CD"))
        #expect(!PlantCode.isValid("ab-cd"))
        #expect(!PlantCode.isValid("ABCD"))
    }

    @Test func generateSkipsUsedCodes() throws {
        var first = SeededGenerator(seed: 7)
        let taken = PlantCode.random(using: &first).rawValue

        var second = SeededGenerator(seed: 7)
        let code = try PlantCode.generate(excluding: [taken], using: &second)
        #expect(code.rawValue != taken)
        #expect(PlantCode.isValid(code.rawValue))
    }

    @Test func generateThrowsWhenNoFreeCodeIsFound() {
        var generator = ConstantGenerator()
        let onlyCode = PlantCode.random(using: &generator).rawValue
        #expect(throws: PlantCode.GenerationError.exhausted) {
            try PlantCode.generate(excluding: [onlyCode], maxAttempts: 10, using: &generator)
        }
    }

    @Test func urlRoundTrip() throws {
        let code = try #require(PlantCode("AB-23"))
        #expect(code.url.absoluteString == "blattify://plant/AB-23")
        #expect(PlantCode(url: code.url) == code)
    }

    @Test(arguments: ["blattify://plant/AB-23", "BLATTIFY://PLANT/ab-23", "AB-23", " ab23 "])
    func payloadParsing(payload: String) {
        #expect(PlantCode(payload: payload)?.rawValue == "AB-23")
    }

    @Test(arguments: ["https://example.com/plant/AB-23", "blattify://other/AB-23", "blattify://plant/", "hello"])
    func payloadRejectsForeignContent(payload: String) {
        #expect(PlantCode(payload: payload) == nil)
    }
}
