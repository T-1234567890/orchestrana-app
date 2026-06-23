import SwiftUI

struct EisenhowerMatrixView: View {
    let tasks: [TodoItem]
    let onSelectTask: (TodoItem) -> Void
    @State private var topRowHeight: CGFloat = 180
    @State private var bottomRowHeight: CGFloat = 180

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                quadrantCard(
                    title: L("tasks.matrix.do_first.title"),
                    subtitle: L("tasks.matrix.do_first.subtitle"),
                    color: .red,
                    tasks: tasks.filter { $0.matrixQuadrant == .doFirst }
                )
                .readHeight { topRowHeight = max(topRowHeight, $0) }
                .frame(height: topRowHeight)

                quadrantCard(
                    title: L("tasks.matrix.schedule.title"),
                    subtitle: L("tasks.matrix.schedule.subtitle"),
                    color: .blue,
                    tasks: tasks.filter { $0.matrixQuadrant == .schedule }
                )
                .readHeight { topRowHeight = max(topRowHeight, $0) }
                .frame(height: topRowHeight)
            }

            HStack(alignment: .top, spacing: 12) {
                quadrantCard(
                    title: L("tasks.matrix.delegate.title"),
                    subtitle: L("tasks.matrix.delegate.subtitle"),
                    color: .orange,
                    tasks: tasks.filter { $0.matrixQuadrant == .delegate }
                )
                .readHeight { bottomRowHeight = max(bottomRowHeight, $0) }
                .frame(height: bottomRowHeight)

                quadrantCard(
                    title: L("tasks.matrix.eliminate.title"),
                    subtitle: L("tasks.matrix.eliminate.subtitle"),
                    color: .gray,
                    tasks: tasks.filter { $0.matrixQuadrant == .eliminate }
                )
                .readHeight { bottomRowHeight = max(bottomRowHeight, $0) }
                .frame(height: bottomRowHeight)
            }
        }
        .onChange(of: tasks) { _, _ in
            topRowHeight = 180
            bottomRowHeight = 180
        }
    }

    private func quadrantCard(title: String, subtitle: String, color: Color, tasks: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if tasks.isEmpty {
                Text(L("tasks.empty.no_tasks"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
            } else {
                ForEach(tasks) { task in
                    Button {
                        onSelectTask(task)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            if let dueDate = task.dueDate {
                                Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(color.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func readHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self, perform: onChange)
    }
}

private extension TodoItem {
    enum MatrixQuadrant {
        case doFirst
        case schedule
        case delegate
        case eliminate
    }

    var matrixQuadrant: MatrixQuadrant {
        let isImportant = priority == .high || priority == .medium
        let isUrgent: Bool
        if let dueDate {
            isUrgent = dueDate.timeIntervalSinceNow <= 48 * 60 * 60
        } else {
            isUrgent = false
        }

        switch (isImportant, isUrgent) {
        case (true, true):
            return .doFirst
        case (true, false):
            return .schedule
        case (false, true):
            return .delegate
        case (false, false):
            return .eliminate
        }
    }
}
