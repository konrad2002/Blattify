import SwiftUI
import SwiftData

/// GitHub-style yearly activity matrix for one plant with filter chips, legend and day details.
struct ActivityMatrixView: View {
    let plant: Plant

    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var visibleFilters = Set(MatrixFilter.allCases)
    @State private var selectedCell: ActivityMatrixModel.Cell?
    @State private var scrollPosition = ScrollPosition(edge: .leading)

    private static let cellSize: CGFloat = 14
    private static let spacing: CGFloat = 3
    private static var step: CGFloat { cellSize + spacing }
    private static let monthLabelHeight: CGFloat = 16

    var body: some View {
        let model = ActivityMatrixModel(plant: plant, year: year, visibleFilters: visibleFilters)
        let years = ActivityMatrixModel.yearRange(for: plant)

        VStack(alignment: .leading, spacing: 12) {
            yearHeader(years: years)
            filterChips
            HStack(alignment: .top, spacing: 4) {
                weekdayLabels
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        monthLabels(model)
                        grid(model)
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 2)
                }
                .scrollPosition($scrollPosition)
            }
            legend
        }
        .padding(.vertical, 8)
        .onAppear { scrollToRelevantWeek() }
        .onChange(of: year) { scrollToRelevantWeek() }
        .sheet(item: $selectedCell) { cell in
            DayDetailView(plant: plant, date: cell.date)
        }
    }

    // MARK: - Header, filters, legend

    private func yearHeader(years: ClosedRange<Int>) -> some View {
        HStack {
            Button {
                year -= 1
            } label: {
                Label("Previous year", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .disabled(year <= years.lowerBound)

            Spacer()
            Text(verbatim: String(year))
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText(value: Double(year)))
            Spacer()

            Button {
                year += 1
            } label: {
                Label("Next year", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .disabled(year >= years.upperBound)
        }
        .buttonStyle(.borderless)
        .contentShape(.rect)
        // The matrix itself scrolls horizontally, so the year can be swiped on the header.
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -50, year < years.upperBound {
                    withAnimation { year += 1 }
                } else if value.translation.width > 50, year > years.lowerBound {
                    withAnimation { year -= 1 }
                }
            }
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MatrixFilter.allCases, id: \.self) { filter in
                    let isOn = visibleFilters.contains(filter)
                    Button {
                        if isOn {
                            visibleFilters.remove(filter)
                        } else {
                            visibleFilters.insert(filter)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(filter.color)
                                .frame(width: 8, height: 8)
                            Text(filter.title)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isOn ? filter.color.opacity(0.18) : .clear, in: .capsule)
                        .overlay(Capsule().strokeBorder(isOn ? .clear : Color.secondary.opacity(0.4)))
                        .foregroundStyle(isOn ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(MatrixCategory.allCases, id: \.self) { category in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(category.color)
                        .frame(width: 12, height: 12)
                    Text(category.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Legend"))
    }

    // MARK: - Grid

    private var weekdayLabels: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
        return VStack(spacing: Self.spacing) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(verbatim: symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: Self.cellSize)
            }
        }
        .padding(.top, Self.monthLabelHeight + 2)
        .accessibilityHidden(true)
    }

    private func monthLabels(_ model: ActivityMatrixModel) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.monthLabels, id: \.month) { label in
                Text(label.date, format: .dateTime.month(.abbreviated))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: CGFloat(label.column) * Self.step)
            }
        }
        .frame(width: gridWidth(model), height: Self.monthLabelHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func grid(_ model: ActivityMatrixModel) -> some View {
        Canvas { context, _ in
            for cell in model.cells {
                draw(cell, in: &context)
            }
        }
        .frame(width: gridWidth(model), height: 7 * Self.step - Self.spacing)
        .contentShape(.rect)
        .onTapGesture { location in
            let column = Int(location.x / Self.step)
            let row = Int(location.y / Self.step)
            if let cell = model.cell(column: column, row: row), !cell.isFuture {
                selectedCell = cell
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Activity in \(String(model.year))"))
        .accessibilityChildren {
            ForEach(model.cells.filter { !$0.categories.isEmpty }) { cell in
                Color.clear
                    .accessibilityLabel(Text(accessibilityText(for: cell)))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { selectedCell = cell }
            }
        }
    }

    private func draw(_ cell: ActivityMatrixModel.Cell, in context: inout GraphicsContext) {
        let rect = CGRect(
            x: CGFloat(cell.column) * Self.step,
            y: CGFloat(cell.row) * Self.step,
            width: Self.cellSize,
            height: Self.cellSize
        )
        let shape = Path(roundedRect: rect, cornerRadius: 3)

        if cell.categories.isEmpty {
            context.fill(shape, with: .color(Color.matrixEmpty.opacity(cell.isFuture ? 0.45 : 1)))
        } else {
            context.drawLayer { layer in
                layer.clip(to: shape)
                for (segment, category) in zip(Self.segments(of: rect, count: cell.categories.count), cell.categories) {
                    layer.fill(Path(segment), with: .color(category.color))
                }
            }
        }

        if cell.hasMore {
            let dot = CGRect(x: rect.maxX - 4.5, y: rect.minY + 1.5, width: 3, height: 3)
            context.fill(Path(ellipseIn: dot), with: .color(.white))
        }
        if cell.isToday {
            context.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 4),
                           with: .color(.primary), lineWidth: 1.5)
        }
    }

    /// Splits a cell: 1 = full, 2 = left/right, 3 = vertical stripes, 4 = quadrants.
    private static func segments(of rect: CGRect, count: Int) -> [CGRect] {
        switch count {
        case 2:
            let (left, right) = rect.divided(atDistance: rect.width / 2, from: .minXEdge)
            return [left, right]
        case 3:
            let width = rect.width / 3
            return (0..<3).map { CGRect(x: rect.minX + CGFloat($0) * width, y: rect.minY, width: width, height: rect.height) }
        case 4:
            let half = CGSize(width: rect.width / 2, height: rect.height / 2)
            return [
                CGRect(origin: rect.origin, size: half),
                CGRect(origin: CGPoint(x: rect.midX, y: rect.minY), size: half),
                CGRect(origin: CGPoint(x: rect.minX, y: rect.midY), size: half),
                CGRect(origin: CGPoint(x: rect.midX, y: rect.midY), size: half),
            ]
        default:
            return [rect]
        }
    }

    private func gridWidth(_ model: ActivityMatrixModel) -> CGFloat {
        max(0, CGFloat(model.columnCount) * Self.step - Self.spacing)
    }

    /// e.g. "3 March: Soaked, Fertilizing"
    private func accessibilityText(for cell: ActivityMatrixModel.Cell) -> String {
        let day = cell.date.formatted(.dateTime.day().month(.wide))
        let categories = cell.allCategories.map { String(localized: $0.title) }.formatted(.list(type: .and))
        return "\(day): \(categories)"
    }

    /// Shows the current week for this year, the end of the year for past years.
    private func scrollToRelevantWeek() {
        let model = ActivityMatrixModel(year: year, events: [], pests: [])
        if let today = model.cells.first(where: \.isToday) {
            scrollPosition.scrollTo(x: max(0, CGFloat(today.column) * Self.step - 200))
        } else {
            scrollPosition.scrollTo(edge: .trailing)
        }
    }
}

#Preview {
    let container = SampleData.makePreviewContainer()
    let descriptor = FetchDescriptor<Plant>(predicate: #Predicate { $0.code == "CA-9X" })
    let plant = (try? container.mainContext.fetch(descriptor).first) ?? Plant(code: "AB-23", name: "Preview")
    List {
        Section("Activity") {
            ActivityMatrixView(plant: plant)
        }
    }
    .modelContainer(container)
}
