import SwiftUI
import SwiftData

enum HomeLayout: String, CaseIterable {
    case list
    case grid
}

enum PlantSort: String, CaseIterable {
    case name
    /// Longest without water first.
    case lastWatered
    /// Plants that are due first, then by next due date.
    case wateringDue

    var title: LocalizedStringKey {
        switch self {
        case .name: "Name"
        case .lastWatered: "Last watered"
        case .wateringDue: "Watering due"
        }
    }
}

/// Home screen: searchable list or grid of all active plants.
struct PlantListView: View {
    @Environment(AppRouter.self) private var router
    @Query private var plants: [Plant]

    @AppStorage("homeLayout") private var layout: HomeLayout = .list
    @AppStorage("homeSort") private var sort: PlantSort = .name
    @State private var searchText = ""
    @State private var isEnteringCode = false

    init() {
        let active = PlantStatus.active.rawValue
        _plants = Query(filter: #Predicate<Plant> { $0.statusRaw == active })
    }

    var body: some View {
        content
            .navigationTitle("Plants")
            .searchable(text: $searchText, prompt: Text("Name, species or code"))
            .toolbar { toolbarContent }
            .sheet(isPresented: $isEnteringCode) {
                CodeEntrySheet { plant in
                    router.showPlant(plant)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        let visiblePlants = sortedFilteredPlants
        if plants.isEmpty {
            ContentUnavailableView {
                Label("No plants yet", systemImage: "leaf")
            } description: {
                Text("Add your first plant to start tracking its care.")
            } actions: {
                Button("Create first plant") { router.createPlant() }
                    .buttonStyle(.glassProminent)
            }
        } else if visiblePlants.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            switch layout {
            case .list:
                List(visiblePlants) { plant in
                    NavigationLink(value: Route.plant(plant)) {
                        PlantRow(plant: plant)
                    }
                }
            case .grid:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                        ForEach(visiblePlants) { plant in
                            NavigationLink(value: Route.plant(plant)) {
                                PlantCard(plant: plant)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Layout", selection: $layout) {
                    Label("List", systemImage: "list.bullet").tag(HomeLayout.list)
                    Label("Grid", systemImage: "square.grid.2x2").tag(HomeLayout.grid)
                }
                Picker("Sort by", selection: $sort) {
                    ForEach(PlantSort.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Label("View options", systemImage: "line.3.horizontal.decrease")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                router.isScanning = true
            } label: {
                Label("Scan QR code", systemImage: "qrcode.viewfinder")
            }
            Button {
                isEnteringCode = true
            } label: {
                Label("Enter code", systemImage: "number")
            }
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                router.createPlant()
            } label: {
                Label("New plant", systemImage: "plus")
            }
        }
    }

    private var sortedFilteredPlants: [Plant] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? plants : plants.filter { plant in
            plant.name.localizedStandardContains(query)
                || plant.species.localizedStandardContains(query)
                || plant.code.localizedStandardContains(query)
        }
        switch sort {
        case .name:
            return filtered.sorted(by: Self.isOrderedByName)
        case .lastWatered:
            // Never watered first, then oldest watering first.
            return Self.sorted(filtered) { $0.lastWatering?.date ?? .distantPast }
        case .wateringDue:
            // Plants without a reminder go last.
            return Self.sorted(filtered) { $0.nextWateringDate() ?? .distantFuture }
        }
    }

    private static func isOrderedByName(_ lhs: Plant, _ rhs: Plant) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    /// Sorts ascending by a date computed once per plant; ties are ordered by name.
    private static func sorted(_ plants: [Plant], by date: (Plant) -> Date) -> [Plant] {
        let keyed: [(plant: Plant, date: Date)] = plants.map { ($0, date($0)) }
        let ordered = keyed.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return isOrderedByName(lhs.plant, rhs.plant)
        }
        return ordered.map(\.plant)
    }
}

#Preview {
    NavigationStack {
        PlantListView()
    }
    .environment(AppRouter())
    .modelContainer(SampleData.makePreviewContainer())
}
