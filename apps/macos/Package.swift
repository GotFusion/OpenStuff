// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenStaffMacOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenStaffApp", targets: ["OpenStaffApp"]),
        .executable(name: "OpenStaffExecutorHelper", targets: ["OpenStaffExecutorHelper"]),
        .executable(name: "OpenStaffCaptureCLI", targets: ["OpenStaffCaptureCLI"]),
        .executable(name: "OpenStaffTaskSlicerCLI", targets: ["OpenStaffTaskSlicerCLI"]),
        .executable(name: "OpenStaffKnowledgeBuilderCLI", targets: ["OpenStaffKnowledgeBuilderCLI"]),
        .executable(name: "OpenStaffOrchestratorCLI", targets: ["OpenStaffOrchestratorCLI"]),
        .executable(name: "OpenStaffAssistCLI", targets: ["OpenStaffAssistCLI"]),
        .executable(name: "OpenStaffReplayVerifyCLI", targets: ["OpenStaffReplayVerifyCLI"]),
        .executable(name: "OpenStaffOpenClawCLI", targets: ["OpenStaffOpenClawCLI"]),
        .executable(name: "OpenStaffStudentCLI", targets: ["OpenStaffStudentCLI"])
    ],
    targets: [
        .target(
            name: "OpenStaffExecutorShared",
            path: "Sources/OpenStaffExecutorShared"
        ),
        .executableTarget(
            name: "OpenStaffApp",
            dependencies: ["OpenStaffExecutorShared"],
            path: "Sources/OpenStaffApp"
        ),
        .executableTarget(
            name: "OpenStaffExecutorHelper",
            dependencies: ["OpenStaffExecutorShared"],
            path: "Sources/OpenStaffExecutorHelper"
        ),
        .executableTarget(
            name: "OpenStaffCaptureCLI",
            path: "Sources/OpenStaffCaptureCLI"
        ),
        .executableTarget(
            name: "OpenStaffTaskSlicerCLI",
            path: "Sources/OpenStaffTaskSlicerCLI"
        ),
        .executableTarget(
            name: "OpenStaffKnowledgeBuilderCLI",
            path: "Sources/OpenStaffKnowledgeBuilderCLI"
        ),
        .executableTarget(
            name: "OpenStaffOrchestratorCLI",
            path: "Sources/OpenStaffOrchestratorCLI"
        ),
        .executableTarget(
            name: "OpenStaffAssistCLI",
            path: "Sources/OpenStaffAssistCLI"
        ),
        .executableTarget(
            name: "OpenStaffReplayVerifyCLI",
            path: "Sources/OpenStaffReplayVerifyCLI"
        ),
        .executableTarget(
            name: "OpenStaffOpenClawCLI",
            path: "Sources/OpenStaffOpenClawCLI"
        ),
        .executableTarget(
            name: "OpenStaffStudentCLI",
            path: "Sources/OpenStaffStudentCLI"
        ),
        .testTarget(
            name: "OpenStaffAppTests",
            dependencies: ["OpenStaffApp"],
            path: "Tests/OpenStaffAppTests"
        )
    ]
)
