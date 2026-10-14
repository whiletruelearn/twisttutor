// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TwistTutorKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CubeCore", targets: ["CubeCore"]),
        .library(name: "CubeValidation", targets: ["CubeValidation"]),
        .library(name: "CubeSolver", targets: ["CubeSolver"]),
        .executable(name: "SolverTools", targets: ["SolverTools"]),
        .library(name: "AppWorkflow", targets: ["AppWorkflow"]),
    ],
    targets: [
        .target(name: "CubeCore"),
        .target(name: "CubeValidation", dependencies: ["CubeCore"]),
        .target(name: "CubeSolver", dependencies: ["CubeCore", "CubeValidation"], resources: [.process("Resources")]),
        .executableTarget(name: "SolverTools", dependencies: ["CubeSolver", "CubeCore"]),
        .target(name: "AppWorkflow", dependencies: ["CubeCore", "CubeValidation", "CubeSolver"]),
        .testTarget(name: "TwistTutorKitTests", dependencies: ["CubeCore", "CubeValidation", "AppWorkflow", "CubeSolver"]),
    ]
)
