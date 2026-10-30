// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MailCore2",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "MailCore2",
            targets: ["MailCore2"]),
    ],
    targets: [
        .binaryTarget(
            name: "MailCore2",
            path: "MailCore.xcframework")
    ]
)
