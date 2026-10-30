// MailCore SPM 适配层。
// binaryTarget (MailCoreBinary.xcframework) 无法声明 linkerSettings，
// 通过本空 target 向链接器传递 MailCore 动态库所需的系统依赖：
//   - .linkedFramework/.linkedLibrary 生成 autolink 条目
//   - 消费方通过 product "MailCore" 依赖本 target，进而带出二进制框架
import Foundation

/// SPM 适配层版本号，仅用于保证模块非空。
public let mailCoreSPMAdapterVersion = "1.0"
