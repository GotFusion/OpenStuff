import AppKit
import ApplicationServices
import CoreGraphics
import CryptoKit
import Foundation

struct CaptureSemanticContextResolver {
    private let screenshotAnchorSize: CGFloat
    private let screenshotAfterDelayMilliseconds: UInt32

    init(
        screenshotAnchorSize: CGFloat = 48,
        screenshotAfterDelayMilliseconds: UInt32 = 120
    ) {
        self.screenshotAnchorSize = screenshotAnchorSize
        self.screenshotAfterDelayMilliseconds = screenshotAfterDelayMilliseconds
    }

    func snapshot(
        pointer: PointerLocation? = nil,
        action: RawEventAction? = nil,
        includeWindowContext: Bool = true
    ) -> ContextSnapshot {
        var diagnostics: [ContextCaptureDiagnostic] = []
        let screenshotAnchors = captureScreenshotAnchors(
            pointer: pointer,
            action: action,
            diagnostics: &diagnostics
        )

        guard let app = NSWorkspace.shared.frontmostApplication else {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: ContextCaptureDiagnosticCode.frontmostAppUnavailable.rawValue,
                    field: "app",
                    message: "无法解析当前前台应用。"
                )
            )

            return ContextSnapshot(
                appName: "Unknown",
                appBundleId: "unknown.bundle.id",
                windowTitle: nil,
                windowId: nil,
                isFrontmost: true,
                screenshotAnchors: screenshotAnchors,
                captureDiagnostics: diagnostics
            )
        }

        let appName = app.localizedName ?? "Unknown"
        let appBundleId = app.bundleIdentifier ?? "unknown.bundle.id"

        guard includeWindowContext else {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: ContextCaptureDiagnosticCode.axCaptureDisabled.rawValue,
                    field: "windowContext",
                    message: "当前采集处于降级模式，未抓取 AX 窗口与焦点元素上下文。"
                )
            )

            return ContextSnapshot(
                appName: appName,
                appBundleId: appBundleId,
                windowTitle: nil,
                windowId: nil,
                isFrontmost: true,
                screenshotAnchors: screenshotAnchors,
                captureDiagnostics: diagnostics
            )
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        let windowContext = captureWindowContext(
            appElement: appElement,
            appBundleId: appBundleId,
            diagnostics: &diagnostics
        )
        let focusedElement = captureFocusedElement(
            appElement: appElement,
            diagnostics: &diagnostics
        )

        return ContextSnapshot(
            appName: appName,
            appBundleId: appBundleId,
            windowTitle: windowContext.title,
            windowId: windowContext.windowId,
            isFrontmost: true,
            windowSignature: windowContext.signature,
            focusedElement: focusedElement,
            screenshotAnchors: screenshotAnchors,
            captureDiagnostics: diagnostics
        )
    }

    private func captureWindowContext(
        appElement: AXUIElement,
        appBundleId: String,
        diagnostics: inout [ContextCaptureDiagnostic]
    ) -> (title: String?, windowId: String?, signature: WindowSignature?) {
        guard let windowElement = axElementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement) else {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: ContextCaptureDiagnosticCode.axWindowUnavailable.rawValue,
                    field: "windowContext",
                    message: "无法读取当前聚焦窗口。"
                )
            )
            return (nil, nil, nil)
        }

        let title = stringAttribute(kAXTitleAttribute as CFString, from: windowElement)
        let windowId = stringAttribute("AXWindowNumber" as CFString, from: windowElement)
        let signature = buildWindowSignature(
            windowElement: windowElement,
            appBundleId: appBundleId,
            windowTitle: title
        )

        if signature == nil {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: ContextCaptureDiagnosticCode.axWindowSignatureUnavailable.rawValue,
                    field: "windowSignature",
                    message: "无法生成当前窗口稳定签名。"
                )
            )
        }

        return (title, windowId, signature)
    }

    private func captureFocusedElement(
        appElement: AXUIElement,
        diagnostics: inout [ContextCaptureDiagnostic]
    ) -> FocusedElementSnapshot? {
        guard let focusedElement = axElementAttribute(kAXFocusedUIElementAttribute as CFString, from: appElement) else {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: ContextCaptureDiagnosticCode.axFocusedElementUnavailable.rawValue,
                    field: "focusedElement",
                    message: "无法读取当前焦点元素。"
                )
            )
            return nil
        }

        let role = stringAttribute(kAXRoleAttribute as CFString, from: focusedElement)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: focusedElement)
        let title = stringAttribute(kAXTitleAttribute as CFString, from: focusedElement)
        let identifier = stringAttribute("AXIdentifier" as CFString, from: focusedElement)
        let descriptionText = stringAttribute(kAXDescriptionAttribute as CFString, from: focusedElement)
        let helpText = stringAttribute(kAXHelpAttribute as CFString, from: focusedElement)
        let boundingRect = boundingRect(from: focusedElement)
        let valueRedacted = shouldRedactValue(forRole: role)

        if role == nil,
           subrole == nil,
           title == nil,
           identifier == nil,
           descriptionText == nil,
           helpText == nil,
           boundingRect == nil {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: ContextCaptureDiagnosticCode.axFocusedElementUnavailable.rawValue,
                    field: "focusedElement",
                    message: "读取到焦点元素句柄，但可读属性为空。"
                )
            )
            return nil
        }

        return FocusedElementSnapshot(
            role: role,
            subrole: subrole,
            title: title,
            identifier: identifier,
            descriptionText: descriptionText,
            helpText: helpText,
            boundingRect: boundingRect,
            valueRedacted: valueRedacted
        )
    }

    private func buildWindowSignature(
        windowElement: AXUIElement,
        appBundleId: String,
        windowTitle: String?
    ) -> WindowSignature? {
        let role = stringAttribute(kAXRoleAttribute as CFString, from: windowElement)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: windowElement)
        let normalizedTitle = normalizedWindowTitle(windowTitle)
        let sizeBucket = sizeBucket(for: boundingRect(from: windowElement))

        let signatureInput = [
            appBundleId,
            role ?? "",
            subrole ?? "",
            normalizedTitle ?? "",
            sizeBucket ?? ""
        ].joined(separator: "|")

        guard !signatureInput.isEmpty else {
            return nil
        }

        let digest = SHA256.hash(data: Data(signatureInput.utf8))
        let signature = digest.prefix(12).map { String(format: "%02x", $0) }.joined()

        return WindowSignature(
            signature: signature,
            normalizedTitle: normalizedTitle,
            role: role,
            subrole: subrole,
            sizeBucket: sizeBucket
        )
    }

    private func normalizedWindowTitle(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.lowercased()
    }

    private func sizeBucket(for rect: SemanticBoundingRect?) -> String? {
        guard let rect else {
            return nil
        }

        let widthBucket = max(Int(rect.width.rounded() / 100), 1)
        let heightBucket = max(Int(rect.height.rounded() / 100), 1)
        return "\(widthBucket)x\(heightBucket)"
    }

    private func captureScreenshotAnchors(
        pointer: PointerLocation?,
        action: RawEventAction?,
        diagnostics: inout [ContextCaptureDiagnostic]
    ) -> [ScreenshotAnchor] {
        guard let pointer, let action, action.source == .mouse else {
            return []
        }

        guard hasScreenCapturePermission() else {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: ContextCaptureDiagnosticCode.screenshotPermissionDenied.rawValue,
                    field: "screenshotAnchors",
                    message: "未授予屏幕录制权限，无法生成轻量截图锚点。"
                )
            )
            return []
        }

        var anchors: [ScreenshotAnchor] = []

        if let beforeAnchor = captureScreenshotAnchor(phase: .before, pointer: pointer) {
            anchors.append(beforeAnchor)
        } else {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: ContextCaptureDiagnosticCode.screenshotCaptureFailed.rawValue,
                    field: "screenshotAnchors",
                    message: "无法捕获操作前截图锚点。"
                )
            )
        }

        if screenshotAfterDelayMilliseconds > 0 {
            Thread.sleep(forTimeInterval: TimeInterval(screenshotAfterDelayMilliseconds) / 1_000)
        }

        if let afterAnchor = captureScreenshotAnchor(phase: .after, pointer: pointer) {
            anchors.append(afterAnchor)
        } else {
            diagnostics.append(
                ContextCaptureDiagnostic(
                    code: ContextCaptureDiagnosticCode.screenshotCaptureFailed.rawValue,
                    field: "screenshotAnchors",
                    message: "无法捕获操作后截图锚点。"
                )
            )
        }

        return anchors
    }

    private func captureScreenshotAnchor(
        phase: ScreenshotAnchorPhase,
        pointer: PointerLocation
    ) -> ScreenshotAnchor? {
        let point = CGPoint(x: pointer.x, y: pointer.y)
        guard let screen = screen(containing: point),
              let displayID = displayID(for: screen) else {
            return nil
        }

        let captureRect = screenshotRect(around: point, within: screen.frame)
        guard !captureRect.isNull,
              captureRect.width > 0,
              captureRect.height > 0 else {
            return nil
        }

        let pixelRect = displayPixelRect(for: captureRect, on: screen)
        guard let image = CGDisplayCreateImage(displayID, rect: pixelRect),
              let fingerprint = fingerprint(for: image) else {
            return nil
        }

        return ScreenshotAnchor(
            phase: phase,
            boundingRect: SemanticBoundingRect(
                x: captureRect.origin.x,
                y: captureRect.origin.y,
                width: captureRect.width,
                height: captureRect.height,
                coordinateSpace: .screen
            ),
            sampleSize: ScreenshotAnchorSampleSize(
                width: image.width,
                height: image.height
            ),
            pixelHash: fingerprint.hash,
            averageLuma: fingerprint.averageLuma
        )
    }

    private func screenshotRect(around point: CGPoint, within screenFrame: CGRect) -> CGRect {
        let halfSize = screenshotAnchorSize / 2
        let rawRect = CGRect(
            x: point.x - halfSize,
            y: point.y - halfSize,
            width: screenshotAnchorSize,
            height: screenshotAnchorSize
        )
        return rawRect.intersection(screenFrame)
    }

    private func displayPixelRect(for screenRect: CGRect, on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let scale = screen.backingScaleFactor
        let localRect = CGRect(
            x: screenRect.origin.x - screenFrame.origin.x,
            y: screenRect.origin.y - screenFrame.origin.y,
            width: screenRect.width,
            height: screenRect.height
        )

        return CGRect(
            x: localRect.origin.x * scale,
            y: (screenFrame.height - localRect.maxY) * scale,
            width: localRect.width * scale,
            height: localRect.height * scale
        )
    }

    private func fingerprint(for image: CGImage) -> (hash: String, averageLuma: Double)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: rect)

        var totalLuma = 0.0
        for index in stride(from: 0, to: bytes.count, by: bytesPerPixel) {
            let red = Double(bytes[index])
            let green = Double(bytes[index + 1])
            let blue = Double(bytes[index + 2])
            totalLuma += (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        }

        let averageLuma = (totalLuma / Double(width * height)) / 255.0
        let roundedAverage = (averageLuma * 1_000).rounded() / 1_000
        let digest = SHA256.hash(data: Data(bytes))
        let hash = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return (hash, roundedAverage)
    }

    private func hasScreenCapturePermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private func axElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return value as? String
    }

    private func boundingRect(from element: AXUIElement) -> SemanticBoundingRect? {
        guard let position = pointAttribute(kAXPositionAttribute as CFString, from: element),
              let size = sizeAttribute(kAXSizeAttribute as CFString, from: element) else {
            return nil
        }

        return SemanticBoundingRect(
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height,
            coordinateSpace: .screen
        )
    }

    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetType(axValue as! AXValue) == .cgPoint,
              AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetType(axValue as! AXValue) == .cgSize,
              AXValueGetValue(axValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func shouldRedactValue(forRole role: String?) -> Bool {
        guard let role else {
            return false
        }

        return [
            "AXSecureTextField"
        ].contains(role)
    }
}

private enum ContextCaptureDiagnosticCode: String {
    case frontmostAppUnavailable = "CTX-FRONTMOST-APP-UNAVAILABLE"
    case axCaptureDisabled = "CTX-AX-CAPTURE-DISABLED"
    case axWindowUnavailable = "CTX-AX-WINDOW-UNAVAILABLE"
    case axWindowSignatureUnavailable = "CTX-AX-WINDOW-SIGNATURE-UNAVAILABLE"
    case axFocusedElementUnavailable = "CTX-AX-FOCUSED-ELEMENT-UNAVAILABLE"
    case screenshotPermissionDenied = "CTX-SCREENSHOT-PERMISSION-DENIED"
    case screenshotCaptureFailed = "CTX-SCREENSHOT-CAPTURE-FAILED"
}
