import CoreData
import Foundation
import SwiftData

/// Keeps watering notifications in sync with the data. Instead of hooking every place that changes
/// a plant or logs a watering, it reschedules after any local save, any iCloud import, app launch,
/// returning to the foreground and reminder-time changes (debounced).
@Observable
final class ReminderCoordinator {
    private let container: ModelContainer
    @ObservationIgnored private var pendingUpdate: Task<Void, Never>?
    @ObservationIgnored private var observers: [Task<Void, Never>] = []

    init(container: ModelContainer) {
        self.container = container
    }

    func start() {
        guard observers.isEmpty else { return }
        observers = [
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave).map({ _ in () }) {
                    self?.setNeedsUpdate()
                }
            },
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange).map({ _ in () }) {
                    self?.setNeedsUpdate()
                }
            },
        ]
        setNeedsUpdate()
    }

    /// Reschedules shortly after the last call, so a burst of saves results in one update.
    func setNeedsUpdate() {
        pendingUpdate?.cancel()
        pendingUpdate = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    private func reschedule() async {
        let active = PlantStatus.active.rawValue
        let descriptor = FetchDescriptor<Plant>(predicate: #Predicate { $0.statusRaw == active && $0.wateringIntervalDays != nil })
        guard let plants = try? container.mainContext.fetch(descriptor) else { return }

        let inputs = plants.compactMap { plant -> WateringReminderPlanner.PlantInput? in
            guard let dueDay = plant.nextWateringDate() else { return nil }
            return WateringReminderPlanner.PlantInput(id: plant.id, name: plant.name, dueDay: dueDay)
        }
        let duePlantIDs = Set(plants.filter { $0.isWateringDue() }.map(\.id))
        let reminders = WateringReminderPlanner.reminders(for: inputs,
                                                          minutesAfterMidnight: ReminderSettings.minutesAfterMidnight)
        await ReminderScheduler.apply(reminders, duePlantIDs: duePlantIDs)
    }
}
