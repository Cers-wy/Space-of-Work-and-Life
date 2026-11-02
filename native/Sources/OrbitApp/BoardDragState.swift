import SwiftUI
import OrbitCore

/// Pointer updates have their own publisher, observed only by the small drag preview.
@MainActor
final class BoardDragCursor: ObservableObject {
    @Published var point: CGPoint = .zero
}
@MainActor
final class BoardDragState: ObservableObject {
    @Published private(set) var task: OrbitTask?
    @Published private(set) var target: TaskStatus?
    let cursor = BoardDragCursor()
    func update(task: OrbitTask? = nil, point: CGPoint, frames: [TaskStatus: CGRect], viewport: CGRect) {
        if let task, self.task?.id != task.id { self.task = task }
        let next = viewport.contains(point) ? frames.first { $0.value.contains(point) }?.key : nil
        if target != next { target = next }
        cursor.point = point
    }
    func reset() { task = nil; target = nil }
}

struct BoardDragPreview: View {
    @ObservedObject var drag: BoardDragState
    let palette: OrbitPalette
    var body: some View {
        if let task = drag.task {
            MovingTaskPreview(task: task, palette: palette, cursor: drag.cursor)
        }
    }
}
private struct MovingTaskPreview: View {
    let task: OrbitTask
    let palette: OrbitPalette
    @ObservedObject var cursor: BoardDragCursor
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CategoryBadge(category: task.category)
            Text(task.title).orbitFont(14, weight: .semibold).lineLimit(3)
        }.padding(16).frame(width: 240, alignment: .leading)
            .background(palette.dark ? Color(hex: 0x272727) : .white,
                        in: RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: SpaceStyle.cornerRadius).strokeBorder(palette.accent) }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .position(cursor.point).allowsHitTesting(false)
    }
}
