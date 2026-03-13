import Foundation

struct FrontmostContextResolver {
    private let resolver: CaptureSemanticContextResolver

    init(resolver: CaptureSemanticContextResolver = CaptureSemanticContextResolver()) {
        self.resolver = resolver
    }

    func snapshot(
        pointer: PointerLocation? = nil,
        action: RawEventAction? = nil
    ) -> ContextSnapshot {
        resolver.snapshot(
            pointer: pointer,
            action: action,
            includeWindowContext: true
        )
    }
}
