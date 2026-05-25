import Foundation
import Security

final class KeychainStore {
    private let service = "com.taki5cm.crt.credentials"

    func value(for account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    func set(_ value: String, for account: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if value.isEmpty {
            SecItemDelete(baseQuery as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var insertQuery = baseQuery
            insertQuery[kSecValueData as String] = data
            let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw AnalysisError.remote("키체인에 정보를 저장하지 못했습니다.")
            }
        } else if status != errSecSuccess {
            throw AnalysisError.remote("키체인에 정보를 저장하지 못했습니다.")
        }
    }
}
