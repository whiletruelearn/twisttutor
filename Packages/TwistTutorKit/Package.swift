// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TwistTutorKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CubeCore", targets: ["CubeCore"]),
        .library(name: "CubeValidation", targets: ["CubeValidation"]),
        .library(name: "AppWorkflow", targets: ["AppWorkflow"]),
    ],
    targets: [
        .target(name: "CubeCore"),
        .target(name: "CubeValidation", dependencies: ["CubeCore"]),
        .target(name: "AppWorkflow", dependencies: ["CubeCore", "CubeValidation"]),
        .testTarget(name: "TwistTutorKitTests", dependencies: ["CubeCore", "CubeValidation", "AppWorkflow"]),
    ]
)
