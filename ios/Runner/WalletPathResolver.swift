import Foundation
import Security

private let walletDbNameKey = "zcash_wallet_db_name"
private let secureStoreService = "com.keplr.vizor.secure_store"

enum WalletPathResolverError: Error {
    case dbNameMissing
    case invalidDbNameData
    case keychainStatus(OSStatus)
}

func resolveWalletDbPath() throws -> String {
    let supportDir = try resolveWalletSupportDirectory()
    let dbName = try resolveWalletDbName()
    return supportDir.appendingPathComponent(dbName).path
}

func resolveWalletSupportDirectory() throws -> URL {
    let supportDir = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    try FileManager.default.createDirectory(
        at: supportDir,
        withIntermediateDirectories: true
    )
    return supportDir
}

private func resolveWalletDbName() throws -> String {
    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccount: walletDbNameKey,
        kSecAttrService: secureStoreService,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
        guard let data = item as? Data else {
            throw WalletPathResolverError.invalidDbNameData
        }
        guard let dbName = String(data: data, encoding: .utf8), !dbName.isEmpty else {
            throw WalletPathResolverError.invalidDbNameData
        }
        return dbName
    case errSecItemNotFound:
        throw WalletPathResolverError.dbNameMissing
    default:
        throw WalletPathResolverError.keychainStatus(status)
    }
}
