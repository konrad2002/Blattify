import SwiftUI
import SwiftData
import UserNotifications

@main
struct BlattifyApp: App {
    /// `nil` if the persistent store could not be opened; the error is shown instead of crashing.
    private let modelContainer: ModelContainer?
    private let storeError: Error?
    private let reminderCoordinator: ReminderCoordinator?
    /// Must be the notification center's delegate before launch finishes to receive cold-start taps.
    @State private var notificationHandler: NotificationHandler

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let handler = NotificationHandler()
        UNUserNotificationCenter.current().delegate = handler
        _notificationHandler = State(initialValue: handler)

        do {
            let container = try Persistence.makeContainer()
            modelContainer = container
            reminderCoordinator = ReminderCoordinator(container: container)
            storeError = nil
        } catch {
            modelContainer = nil
            reminderCoordinator = nil
            storeError = error
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer, let reminderCoordinator {
                ContentView()
                    .modelContainer(modelContainer)
                    .environment(reminderCoordinator)
                    .environment(notificationHandler)
                    .task { reminderCoordinator.start() }
                    .onChange(of: scenePhase) { _, phase in
                        // Overdue reminders move to the next reminder time when the app comes back.
                        if phase == .active {
                            reminderCoordinator.setNeedsUpdate()
                        }
                    }
            } else {
                ContentUnavailableView(
                    "Data could not be loaded",
                    systemImage: "exclamationmark.triangle",
                    description: Text(verbatim: storeError?.localizedDescription ?? "")
                )
            }
        }
    }
}
