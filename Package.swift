// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Emote",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "EmoteCore", targets: ["EmoteCore"]),
    .executable(name: "EmoteCLI", targets: ["EmoteCLI"]),
    .executable(name: "EmoteApp", targets: ["EmoteApp"]),
  ],
  targets: [
    .target(
      name: "EmoteCore",
      exclude: [
        "Resources/emoji-cldr-48.2.tsv",
        "Resources/CLDR-LICENSE.txt",
      ],
      resources: [
        .copy("Resources/emoji-test-17.0.txt"),
      ]
    ),
    .executableTarget(
      name: "EmoteCLI",
      dependencies: ["EmoteCore"]
    ),
    .executableTarget(
      name: "EmoteApp",
      dependencies: ["EmoteCore"],
      exclude: ["Info.plist"]
    ),
    .testTarget(
      name: "EmoteCoreTests",
      dependencies: ["EmoteCore"]
    ),
  ]
)
