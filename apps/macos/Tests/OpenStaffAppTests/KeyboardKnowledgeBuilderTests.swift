import Foundation
import XCTest
@testable import OpenStaffApp

final class KeyboardKnowledgeBuilderTests: XCTestCase {
    func testBuildCombinesInputAndReturnIntoSingleKnowledgeStep() {
        let chunk = makeChunk(eventIds: ["k1", "k2", "k3", "m1"], eventCount: 4)
        let rawEventIndex: [String: RawEvent] = [
            "k1": makeKeyDownEvent(eventId: "k1", keyCode: 4, characters: "h", charactersIgnoringModifiers: "h"),
            "k2": makeKeyDownEvent(eventId: "k2", keyCode: 34, characters: "i", charactersIgnoringModifiers: "i"),
            "k3": makeKeyDownEvent(eventId: "k3", keyCode: 36, characters: "\r", charactersIgnoringModifiers: "\r"),
            "m1": makeMouseClickEvent(eventId: "m1", x: 320, y: 240)
        ]

        let builder = KnowledgeItemBuilder()
        let item = builder.build(from: chunk, rawEventIndex: rawEventIndex)

        XCTAssertEqual(item.steps.count, 2)
        XCTAssertTrue(item.steps[0].instruction.contains("输入\"hi\"并按回车"))
        XCTAssertEqual(item.steps[0].sourceEventIds, ["k1", "k2", "k3"])
        XCTAssertNil(item.steps[0].target)
        XCTAssertTrue(item.steps[1].instruction.contains("点击"))
        XCTAssertEqual(item.steps[1].sourceEventIds, ["m1"])
        XCTAssertEqual(item.steps[1].target?.coordinate?.x, 320)
        XCTAssertEqual(item.steps[1].target?.coordinate?.y, 240)
        XCTAssertEqual(item.steps[1].target?.semanticTargets.first?.locatorType, .coordinateFallback)
        XCTAssertEqual(item.steps[1].target?.preferredLocatorType, .coordinateFallback)
    }

    func testBuildCreatesShortcutStepFromModifierKeyDown() {
        let chunk = makeChunk(eventIds: ["k1"], eventCount: 1)
        let rawEventIndex: [String: RawEvent] = [
            "k1": makeKeyDownEvent(
                eventId: "k1",
                keyCode: 8,
                characters: "c",
                charactersIgnoringModifiers: "c",
                modifiers: [.command]
            )
        ]

        let builder = KnowledgeItemBuilder()
        let item = builder.build(from: chunk, rawEventIndex: rawEventIndex)

        XCTAssertEqual(item.steps.count, 1)
        XCTAssertTrue(item.steps[0].instruction.contains("快捷键 command+c"))
        XCTAssertEqual(item.steps[0].sourceEventIds, ["k1"])
        XCTAssertNil(item.steps[0].target)
    }

    func testBuildPointerStepCreatesCoordinateFallbackSemanticTarget() throws {
        let chunk = makeChunk(eventIds: ["m1"], eventCount: 1)
        let rawEventIndex: [String: RawEvent] = [
            "m1": makeMouseClickEvent(eventId: "m1", x: 320, y: 240)
        ]

        let builder = KnowledgeItemBuilder()
        let item = builder.build(from: chunk, rawEventIndex: rawEventIndex)
        let target = try XCTUnwrap(item.steps.first?.target)
        let semanticTarget = try XCTUnwrap(target.semanticTargets.first)
        let boundingRect = try XCTUnwrap(semanticTarget.boundingRect)

        XCTAssertEqual(target.coordinate?.x, 320)
        XCTAssertEqual(target.coordinate?.y, 240)
        XCTAssertEqual(target.preferredLocatorType, .coordinateFallback)
        XCTAssertEqual(semanticTarget.locatorType, .coordinateFallback)
        XCTAssertEqual(semanticTarget.appBundleId, "com.test.app")
        XCTAssertEqual(semanticTarget.windowTitlePattern, "^Main$")
        XCTAssertEqual(semanticTarget.source, .capture)
        XCTAssertEqual(semanticTarget.confidence, 0.24, accuracy: 0.001)
        XCTAssertEqual(boundingRect.x, 320, accuracy: 0.001)
        XCTAssertEqual(boundingRect.y, 240, accuracy: 0.001)
        XCTAssertEqual(boundingRect.width, 1, accuracy: 0.001)
        XCTAssertEqual(boundingRect.height, 1, accuracy: 0.001)
        XCTAssertEqual(boundingRect.coordinateSpace, .screen)
    }

    func testNormalizedEventDecodesLegacyCoordinateOnlyTarget() throws {
        let payload = """
        {
          "schemaVersion": "capture.normalized.v0",
          "normalizedEventId": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          "sourceEventId": "11111111-1111-4111-8111-111111111111",
          "sessionId": "session-test",
          "timestamp": "2026-03-10T10:00:00Z",
          "eventType": "click",
          "target": {
            "kind": "coordinate",
            "coordinate": {
              "x": 320,
              "y": 240,
              "coordinateSpace": "screen"
            }
          },
          "contextSnapshot": {
            "appName": "TestApp",
            "appBundleId": "com.test.app",
            "windowTitle": "Main",
            "windowId": "1",
            "isFrontmost": true
          },
          "confidence": 1,
          "normalizerVersion": "rule-v0"
        }
        """

        let event = try JSONDecoder().decode(NormalizedEvent.self, from: Data(payload.utf8))

        XCTAssertEqual(event.target.kind, .coordinate)
        XCTAssertEqual(event.target.coordinate.x, 320)
        XCTAssertEqual(event.target.coordinate.y, 240)
        XCTAssertTrue(event.target.semanticTargets.isEmpty)
        XCTAssertNil(event.target.preferredLocatorType)
    }

    private func makeChunk(eventIds: [String], eventCount: Int) -> TaskChunk {
        TaskChunk(
            taskId: "task-session-test-001",
            sessionId: "session-test",
            startTimestamp: "2026-03-10T10:00:00Z",
            endTimestamp: "2026-03-10T10:00:10Z",
            eventIds: eventIds,
            eventCount: eventCount,
            primaryContext: ContextSnapshot(
                appName: "TestApp",
                appBundleId: "com.test.app",
                windowTitle: "Main",
                windowId: "1",
                isFrontmost: true
            ),
            boundaryReason: .sessionEnd
        )
    }

    private func makeKeyDownEvent(
        eventId: String,
        keyCode: Int,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifiers: [KeyboardModifier] = []
    ) -> RawEvent {
        RawEvent(
            eventId: eventId,
            sessionId: "session-test",
            timestamp: "2026-03-10T10:00:00Z",
            source: .keyboard,
            action: .keyDown,
            pointer: PointerLocation(x: 100, y: 100),
            contextSnapshot: ContextSnapshot(
                appName: "TestApp",
                appBundleId: "com.test.app",
                windowTitle: "Main",
                windowId: "1",
                isFrontmost: true
            ),
            modifiers: modifiers,
            keyboard: KeyboardEventPayload(
                keyCode: keyCode,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                isRepeat: false
            )
        )
    }

    private func makeMouseClickEvent(eventId: String, x: Int, y: Int) -> RawEvent {
        RawEvent(
            eventId: eventId,
            sessionId: "session-test",
            timestamp: "2026-03-10T10:00:00Z",
            source: .mouse,
            action: .leftClick,
            pointer: PointerLocation(x: x, y: y),
            contextSnapshot: ContextSnapshot(
                appName: "TestApp",
                appBundleId: "com.test.app",
                windowTitle: "Main",
                windowId: "1",
                isFrontmost: true
            )
        )
    }
}
