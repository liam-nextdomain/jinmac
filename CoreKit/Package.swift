// swift-tools-version: 6.0
import PackageDescription

// 모듈 의존 방향이 곧 설계 제약이다 (요구사항 14.1).
//
//   Model ← Collector            수집: IOKit·sysctl·비공개 API. 판정 쪽으로 새지 않는다
//   Model ← Store                저장: 시스템 SQLite3 직접
//   Model ← Workload ← Verdict   판정: 결정론. Collector·Store를 import하지 않는다
//   Verdict ← Report ← Narrator  문장: Narrator는 판정 결과만 받는다 (A-02)
let package = Package(
    name: "CoreKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Model", targets: ["Model"]),
        .library(name: "Collector", targets: ["Collector"]),
        .library(name: "Store", targets: ["Store"]),
        .library(name: "Workload", targets: ["Workload"]),
        .library(name: "Verdict", targets: ["Verdict"]),
        .library(name: "Report", targets: ["Report"]),
        .library(name: "Narrator", targets: ["Narrator"]),
    ],
    targets: [
        .target(name: "Model"),
        .target(name: "Collector", dependencies: ["Model"]),
        .target(
            name: "Store",
            dependencies: ["Model"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "Workload", dependencies: ["Model"], resources: [.process("Resources")]),
        .target(name: "Verdict", dependencies: ["Model", "Workload"], resources: [.process("Resources")]),
        .target(name: "Report", dependencies: ["Model", "Verdict"]),
        .target(name: "Narrator", dependencies: ["Report"]),
        .testTarget(
            name: "CoreKitTests",
            dependencies: ["Model", "Collector", "Store", "Workload", "Verdict", "Report", "Narrator"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
