// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenStaffMacOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenStaffApp", targets: ["OpenStaffApp"]),
        .executable(name: "OpenStaffCaptureCLI", targets: ["OpenStaffCaptureCLI"]),
        .executable(name: "OpenStaffTaskSlicerCLI", targets: ["OpenStaffTaskSlicerCLI"]),
        .executable(name: "OpenStaffKnowledgeBuilderCLI", targets: ["OpenStaffKnowledgeBuilderCLI"]),
        .executable(name: "OpenStaffOrchestratorCLI", targets: ["OpenStaffOrchestratorCLI"]),
        .executable(name: "OpenStaffAssistCLI", targets: ["OpenStaffAssistCLI"]),
        .executable(name: "OpenStaffStudentCLI", targets: ["OpenStaffStudentCLI"]),
        .executable(name: "OpenStaffDemoCLI", targets: ["OpenStaffDemoCLI"])
    ],
    targets: [
        .executableTarget(
            name: "OpenStaffApp",
            path: "Sources/OpenStaffApp"
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
            name: "OpenStaffStudentCLI",
            path: "Sources/OpenStaffStudentCLI"
        ),
        .executableTarget(
            name: "OpenStaffDemoCLI",
            path: "Sources/OpenStaffDemoCLI"
        ),
        .testTarget(
            name: "OpenStaffAppTests",
            dependencies: ["OpenStaffApp"],
            path: "Tests/OpenStaffAppTests"
        )
    ]
)
