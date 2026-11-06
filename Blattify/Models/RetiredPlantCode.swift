import Foundation
import SwiftData

/// Remembers the code of a permanently deleted plant so it is never handed out again
/// (printed labels for deleted plants must not point to a new plant).
@Model
final class RetiredPlantCode {
    var code: String = ""
    var retiredAt: Date = Date.now

    init(code: String, retiredAt: Date = .now) {
        self.code = code
        self.retiredAt = retiredAt
    }
}
