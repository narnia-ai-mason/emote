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
  dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMinor(from: "0.32.3")),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "3.32.3"),
    .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.9.0"),
    .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.0"),
  ],
  targets: [
    .target(
      name: "EmoteCore",
      resources: [
        .copy("Resources/emoji-test-17.0.txt"),
      ]
    ),
    .target(
      name: "EmoteGemma",
      dependencies: [
        "EmoteCore",
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXVLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "MLXGuidedGeneration", package: "mlx-swift-lm"),
        .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
        .product(name: "HuggingFace", package: "swift-huggingface"),
        .product(name: "Tokenizers", package: "swift-transformers"),
      ]
    ),
    .executableTarget(
      name: "EmoteCLI",
      dependencies: ["EmoteCore", "EmoteGemma"]
    ),
    .executableTarget(
      name: "EmoteApp",
      dependencies: [
        "EmoteCore",
        "EmoteGemma",
      ],
      exclude: ["Info.plist"]
    ),
    .testTarget(
      name: "EmoteCoreTests",
      dependencies: ["EmoteCore"]
    ),
  ]
)
