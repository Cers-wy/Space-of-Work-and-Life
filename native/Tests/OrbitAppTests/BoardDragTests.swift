import XCTest
import Combine
import OrbitCore
@testable import OrbitApp

@MainActor
final class BoardDragTests: XCTestCase {
    func testPointerUpdatesDoNotPublishToBoardOrCardsUntilTargetChanges() {
        let drag = BoardDragState()
        let viewport = CGRect(x: 0, y: 0, width: 600, height: 800)
        let frames: [TaskStatus: CGRect] = [.todo: CGRect(x: 0, y: 0, width: 300, height: 800), .doing: CGRect(x: 300, y: 0, width: 300, height: 800)]
        let task = OrbitTask(title: "隔离拖拽状态")
        drag.update(task: task, point: CGPoint(x: 10, y: 20), frames: frames, viewport: viewport)
        var boardEvents = 0, cursorEvents = 0
        let boardToken = drag.objectWillChange.sink { boardEvents += 1 }
        let cursorToken = drag.cursor.objectWillChange.sink { cursorEvents += 1 }
        for y in 1...500 { drag.update(task: task, point: CGPoint(x: 50, y: y), frames: frames, viewport: viewport) }
        XCTAssertEqual(boardEvents, 0); XCTAssertEqual(cursorEvents, 500)
        drag.update(task: task, point: CGPoint(x: 350, y: 100), frames: frames, viewport: viewport)
        XCTAssertEqual(boardEvents, 1); XCTAssertEqual(drag.target, .doing)
        drag.update(task: task, point: CGPoint(x: 900, y: 100), frames: frames, viewport: viewport)
        XCTAssertNil(drag.target)
        drag.reset(); XCTAssertNil(drag.task)
        withExtendedLifetime([boardToken, cursorToken]) {}
    }
}
