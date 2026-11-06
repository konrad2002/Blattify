import CloudKit
import SwiftUI
import SwiftData

/// App settings: reminders, backup, iCloud status, language and version.
struct SettingsView: View {
    @Environment(ReminderCoordinator.self) private var reminders
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ReminderSettings.minutesKey) private var reminderMinutes = ReminderSettings.defaultMinutes
    @State private var notificationsDenied = false
    @State private var iCloudStatus: CKAccountStatus?
    @State private var isExporting = false
    @State private var exportedFile: URL?
    @State private var isChoosingImportFile = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            reminderSection
            dataSection
            iCloudSection
            Section {
                Button("Change app language", systemImage: "globe", action: openSystemSettings)
            } footer: {
                Text("Blattify uses your iPhone's language. You can choose a different language for Blattify in the Settings app.")
            }
            Section("About") {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .onChange(of: reminderMinutes) {
            reminders.setNeedsUpdate()
        }
        .task(id: scenePhase) {
            notificationsDenied = await ReminderScheduler.isDenied()
            iCloudStatus = try? await CKContainer(identifier: Persistence.cloudKitContainerIdentifier).accountStatus()
        }
        .fileImporter(isPresented: $isChoosingImportFile, allowedContentTypes: [.blattifyBackup]) { result in
            switch result {
            case .success(let url):
                Task { await router.importBackup(from: url, into: modelContext) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var reminderSection: some View {
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

    private var dataSection: some View {
        Section {
            Button {
                Task { await export() }
            } label: {
                HStack {
                    Label("Export all data", systemImage: "square.and.arrow.up.on.square")
                    Spacer()
                    if isExporting {
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)

            if let exportedFile {
                ShareLink(item: exportedFile) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Share or save backup")
                            Text(verbatim: exportedFile.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }

            Button {
                isChoosingImportFile = true
            } label: {
                Label("Import data", systemImage: "square.and.arrow.down")
            }
            .disabled(router.isImporting)
        } header: {
            Text("Backup")
        } footer: {
            Text("A backup contains all plants, entries and photos. Importing adds what is missing and never deletes or overwrites your data.")
        }
    }

    private var iCloudSection: some View {
        Section {
            switch iCloudStatus {
            case .available:
                Label("Syncing with iCloud", systemImage: "checkmark.icloud")
            case .noAccount:
                Label("Not signed in to iCloud", systemImage: "xmark.icloud")
            case .restricted, .temporarilyUnavailable:
                Label("iCloud is currently unavailable", systemImage: "exclamationmark.icloud")
            case .couldNotDetermine, nil:
                Label("Checking iCloud…", systemImage: "icloud")
            @unknown default:
                Label("iCloud is currently unavailable", systemImage: "exclamationmark.icloud")
            }
        } header: {
            Text("iCloud")
        } footer: {
            if iCloudStatus == .noAccount {
                Text("Your plants are stored on this iPhone only. Sign in to iCloud to sync them with your other devices.")
            }
        }
    }

    // MARK: - Actions

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let snapshot = try BackupExporter.makeSnapshot(from: modelContext)
            let directory = FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
            exportedFile = try await BackupExporter.writeArchive(snapshot, to: directory)
        } catch {
            errorMessage = error.localizedDescription
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

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(version) (\(build))"
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
