import SwiftUI

/// Horizontal row of tappable suggestions shown below a text field.
struct SuggestionChips: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions.prefix(10), id: \.self) { suggestion in
                    Button(suggestion) {
                        onSelect(suggestion)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .font(.subheadline)
                }
            }
        }
        .accessibilityLabel(Text("Suggestions"))
    }

    /// Previously used values matching `input`, without the exact current value.
    static func matches(for input: String, in values: [String]) -> [String] {
        let query = input.trimmingCharacters(in: .whitespaces)
        return values.filter { value in
            value != query && (query.isEmpty || value.localizedStandardContains(query))
        }
    }
}

#Preview {
    SuggestionChips(suggestions: ["Monstera deliciosa", "Epipremnum aureum"]) { _ in }
        .padding()
}
