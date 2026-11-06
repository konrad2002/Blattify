import SwiftUI

/// App settings. Export/import and iCloud status follow in Phase 8.
struct SettingsView: View {
    @Environment(ReminderCoordinator.self) private var reminders
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ReminderSettings.minutesKey) private var reminderMinutes = ReminderSettings.defaultMinutes
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section {
                DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
                if notificationsDenied {
                    Label("Notifications are turned off for Blattify.", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Button("Open Settings", action: openSystemSettings)
                }
            } header: {
                Text("Watering reminders")
            } footer: {
                Text("Reminders are sent at this time on the day a plant needs water. Set the interval for each plant in its edit screen.")
            }
        }
        .navigationTitle("Settings")
        .onChange(of: reminderMinutes) {
            reminders.setNeedsUpdate()
        }
        .task(id: scenePhase) {
            notificationsDenied = await ReminderScheduler.isDenied()
        }
    }

    /// Bridges the stored minutes after midnight to a `Date` for the picker.
    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderMinutes = (components.hour ?? 9) * 60 + (components.minute ?? 0)
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
