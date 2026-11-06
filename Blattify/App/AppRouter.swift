import SwiftUI

/// Destinations in the main navigation stack.
enum Route: Hashable {
    case plant(Plant)
}

/// Owns the navigation path so plants can be opened from anywhere (code entry, scanner, deep links).
@Observable
final class AppRouter {
    var path: [Route] = []

    /// Shows the plant's profile as the only screen above the home list.
    func showPlant(_ plant: Plant) {
        path = [.plant(plant)]
    }
}
