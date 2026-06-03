// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "MaestroCLI",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(
      name: "MaestroCLIShared",
      targets: ["MaestroCLIShared"]
    ),
    .executable(
      name: "maestro",
      targets: ["maestro"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.0"),
  ],
  targets: [
    .target(
      name: "MaestroCLIShared",
      path: "Maestro/CLIService/Shared"
    ),
    .executableTarget(
      name: "maestro",
      dependencies: [
        "MaestroCLIShared",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Rainbow", package: "Rainbow"),
      ],
      path: "MaestroCLI"
    ),
    .testTarget(
      name: "MaestroCLITests",
      dependencies: [
        "MaestroCLIShared",
        "maestro",
      ],
      path: "MaestroCLITests"
    ),
  ]
)
