import Foundation
import Security
import CryptoKit

enum CryptoError: LocalizedError {
    case keyGenerationFailed
    case encryptionFailed
    case decryptionFailed
    case keyNotFound
    case invalidKeyData
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed: return "Failed to generate key pair"
        case .encryptionFailed:    return "Encryption failed"
        case .decryptionFailed:    return "Decryption failed"
        case .keyNotFound:         return "Private key not found in Keychain"
        case .invalidKeyData:      return "Invalid key data"
        case .keychainError(let s): return "Keychain error: \(s)"
        }
    }
}

final class CryptoService {
    static let shared = CryptoService()

    private let keyTag = "com.telemax.rsa.private"
    private let keySize = 2048

    private init() {}

    // MARK: - RSA Key Pair Generation

    func generateKeyPair() throws -> (privateKey: SecKey, publicKey: SecKey) {
        deletePrivateKey()

        let attributes: [String: Any] = [
            kSecAttrKeyType as String:       kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: keySize,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String:    true,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw CryptoError.keyGenerationFailed
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CryptoError.keyGenerationFailed
        }
        return (privateKey, publicKey)
    }

    // MARK: - Keychain

    func getPrivateKey() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrKeyType as String:        kSecAttrKeyTypeRSA,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecReturnRef as String:          true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw CryptoError.keyNotFound }
        return result as! SecKey
    }

    func getPublicKey() throws -> SecKey {
        let priv = try getPrivateKey()
        guard let pub = SecKeyCopyPublicKey(priv) else {
            throw CryptoError.keyGenerationFailed
        }
        return pub
    }

    func deletePrivateKey() {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!
        ]
        SecItemDelete(query as CFDictionary)
    }

    var hasKeyPair: Bool { (try? getPrivateKey()) != nil }

    // MARK: - Export / Import

    func exportPublicKey(_ key: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw CryptoError.invalidKeyData
        }
        return data.base64EncodedString()
    }

    func importPublicKey(from base64: String) throws -> SecKey {
        guard let data = Data(base64Encoded: base64) else {
            throw CryptoError.invalidKeyData
        }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String:       kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String:      kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: keySize
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, attrs as CFDictionary, &error) else {
            throw CryptoError.invalidKeyData
        }
        return key
    }

    // MARK: - User ID  (SHA-256 of public key bytes)

    func userId(from publicKey: SecKey) throws -> String {
        let b64 = try exportPublicKey(publicKey)
        guard let raw = Data(base64Encoded: b64) else { throw CryptoError.invalidKeyData }
        let hash = SHA256.hash(data: raw)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Hybrid Encryption  (RSA-OAEP + AES-256-GCM)

    /// Encrypt `message` so that every recipient (keyed by userId) can decrypt it.
    func encrypt(
        message: Data,
        forRecipients publicKeys: [String: SecKey]
    ) throws -> (encryptedKeys: [String: String], encryptedContent: String) {

        // 1. Random AES-256 key
        let aesKey = SymmetricKey(size: .bits256)

        // 2. AES-GCM seal
        let sealed = try AES.GCM.seal(message, using: aesKey)
        guard let combined = sealed.combined else { throw CryptoError.encryptionFailed }
        let encryptedContent = combined.base64EncodedString()

        // 3. RSA-OAEP encrypt AES key for each recipient
        let aesKeyData = aesKey.withUnsafeBytes { Data($0) }
        var encryptedKeys: [String: String] = [:]

        for (uid, pubKey) in publicKeys {
            var err: Unmanaged<CFError>?
            guard let ct = SecKeyCreateEncryptedData(
                pubKey, .rsaEncryptionOAEPSHA256, aesKeyData as CFData, &err
            ) as Data? else {
                throw CryptoError.encryptionFailed
            }
            encryptedKeys[uid] = ct.base64EncodedString()
        }

        return (encryptedKeys, encryptedContent)
    }

    /// Decrypt using own private key.
    func decrypt(encryptedContent: String, encryptedKey: String) throws -> Data {
        let privateKey = try getPrivateKey()

        guard let ekData = Data(base64Encoded: encryptedKey) else {
            throw CryptoError.invalidKeyData
        }

        // RSA decrypt AES key
        var err: Unmanaged<CFError>?
        guard let aesRaw = SecKeyCreateDecryptedData(
            privateKey, .rsaEncryptionOAEPSHA256, ekData as CFData, &err
        ) as Data? else {
            throw CryptoError.decryptionFailed
        }

        let aesKey = SymmetricKey(data: aesRaw)

        // AES-GCM open
        guard let cipherData = Data(base64Encoded: encryptedContent) else {
            throw CryptoError.invalidKeyData
        }
        let box = try AES.GCM.SealedBox(combined: cipherData)
        return try AES.GCM.open(box, using: aesKey)
    }
}
