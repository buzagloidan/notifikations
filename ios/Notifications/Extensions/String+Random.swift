import Foundation
import Security

extension String {
    static func randomSecret(prefix: String, length: Int = 32) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        // Reject bytes ≥ usableRange to eliminate modulo bias.
        // 256 / 36 = 7, so usableRange = 252; bytes 252-255 are discarded.
        let usableRange = chars.count * (256 / chars.count)
        var result = [Character]()
        result.reserveCapacity(length)
        var byte: UInt8 = 0
        while result.count < length {
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            guard status == errSecSuccess else {
                fatalError("SecRandomCopyBytes failed: \(status)")
            }
            if Int(byte) < usableRange {
                result.append(chars[Int(byte) % chars.count])
            }
        }
        return "\(prefix)\(String(result))"
    }
}
