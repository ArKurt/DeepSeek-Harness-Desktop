import Foundation
import CryptoKit

/// 启动时自校验关键文件，防止应用内容被篡改后运行。
/// 常量由 build.sh 在编译前生成（Sources/Integrity.generated.swift）。
enum Integrity {
    /// 启动时一次性计算：关键文件哈希是否与构建时一致（首次访问时求值，全局只算一次）。
    static let passed: Bool = verify()

    /// 校验 Bundle 内关键文件的 SHA256 是否与构建时一致。
    /// - Returns: true = 完整；false = 被篡改（调用方应拒绝启动）
    static func verify() -> Bool {
        let root = Bundle.main.bundleURL
        for (path, expected) in IntegrityChecks.list {
            let url = root.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: url) else {
                NSLog("INTEGRITY: 缺少文件 %@", path)
                return false
            }
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            if digest != expected {
                NSLog("INTEGRITY: 文件哈希不匹配 %@ (期望 %@, 实际 %@)", path, expected, digest)
                return false
            }
        }
        return true
    }
}
