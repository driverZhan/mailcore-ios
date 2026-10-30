// swift-tools-version:5.9
// MailCore 的 Swift Package Manager 描述文件。
// 二进制产物为 lib/MailCore.xcframework（由 ./build-xcframework.sh 生成，动态框架）。
// binaryTarget 不支持 linkerSettings，因此通过 MailCoreSupport 门面 target
// 声明 MailCore 依赖的系统库/框架（与 otool -L 产物依赖清单一致）。
import PackageDescription

let package = Package(
    name: "MailCore",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "MailCore",
            targets: ["MailCoreSupport"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "MailCoreBinary",
            path: "lib/MailCore.xcframework"
        ),
        .target(
            name: "MailCoreSupport",
            dependencies: ["MailCoreBinary"],
            linkerSettings: [
                .linkedFramework("CFNetwork"),
                .linkedFramework("Security"),
                .linkedLibrary("xml2"),
                .linkedLibrary("iconv"),
                .linkedLibrary("z"),
                .linkedLibrary("resolv")
            ]
        )
    ]
)
