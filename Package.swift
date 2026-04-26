// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "CodexQuotaGlass",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "CodexQuotaGlass", targets: ["CodexQuotaGlass"]),
    .library(name: "CodexQuotaKit", targets: ["CodexQuotaKit"])
  ],
  targets: [
    .target(
      name: "CodexQuotaKit"
    ),
    .executableTarget(
      name: "CodexQuotaGlass",
      dependencies: ["CodexQuotaKit"]
    )
  ]
)
