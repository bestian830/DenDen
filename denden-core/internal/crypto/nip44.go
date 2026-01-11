package crypto

import (
	"fmt"

	"github.com/nbd-wtf/go-nostr/nip44"
)

// Encrypt use NIP-44 standard encryption
// NIP-44 provides end-to-end encryption, ensuring only the recipient can decrypt
//
// Parameters:
//   - plaintext: The plaintext message to encrypt
//   - senderPrivKey: The sender's private key (hex string)
//   - recipientPubKey: The recipient's public key (hex string)
//
// Returns:
//   - ciphertext: The encrypted message (Base64 encoded)
//   - error: Encryption error
func Encrypt(plaintext, senderPrivKey, recipientPubKey string) (string, error) {
	// Using NIP-44 encryption
	// Internal process:
	// 1. Use ECDH (Elliptic Curve Diffie-Hellman) to calculate shared key
	// 2. Use ChaCha20-Poly1305 AEAD to encrypt plaintext
	// 3. Return Base64 encoded ciphertext

	// Generate session key (using ECDH to calculate shared key)
	conversationKey, err := nip44.GenerateConversationKey(recipientPubKey, senderPrivKey)
	if err != nil {
		return "", fmt.Errorf("Failed to generate conversation key: %w", err)
	}

	// Encrypt using session key
	ciphertext, err := nip44.Encrypt(plaintext, conversationKey)
	if err != nil {
		return "", fmt.Errorf("Failed to encrypt: %w", err)
	}

	return ciphertext, nil
}

// Decrypt use NIP-44 standard decryption
//
// Parameters:
//   - ciphertext: The encrypted message (Base64 encoded)
//   - recipientPrivKey: The recipient's private key (hex string)
//   - senderPubKey: The sender's public key (hex string)
//
// Returns:
//   - plaintext: The decrypted message
//   - error: Decryption error
func Decrypt(ciphertext, recipientPrivKey, senderPubKey string) (string, error) {
	// Using NIP-44 decryption
	// Internal process:
	// 1. Use ECDH (Elliptic Curve Diffie-Hellman) to calculate shared key (same as encryption)
	// 2. Use ChaCha20-Poly1305 AEAD to decrypt ciphertext
	// 3. Return plaintext

	// Generate session key (using the same public-private key pair as encryption)
	conversationKey, err := nip44.GenerateConversationKey(senderPubKey, recipientPrivKey)
	if err != nil {
		return "", fmt.Errorf("Failed to generate conversation key: %w", err)
	}

	// Decrypt using session key
	plaintext, err := nip44.Decrypt(ciphertext, conversationKey)
	if err != nil {
		return "", fmt.Errorf("Failed to decrypt: %w", err)
	}

	return plaintext, nil
}

// EncryptForMultiple encrypts the same message for multiple recipients
// Each recipient will receive an independent encrypted copy
//
// Parameters:
//   - plaintext: The plaintext message to encrypt
//   - senderPrivKey: The sender's private key
//   - recipientPubKeys: The recipients' public keys
//
// Returns:
//   - map[string]string: Public key -> Ciphertext mapping
//   - error: Encryption error
func EncryptForMultiple(plaintext, senderPrivKey string, recipientPubKeys []string) (map[string]string, error) {
	result := make(map[string]string)

	for _, recipientPubKey := range recipientPubKeys {
		ciphertext, err := Encrypt(plaintext, senderPrivKey, recipientPubKey)
		if err != nil {
			return nil, fmt.Errorf("Failed to encrypt for %s: %w", recipientPubKey[:8], err)
		}
		result[recipientPubKey] = ciphertext
	}

	return result, nil
}

// Security notes for NIP-44 encryption
//
// 1. ECDH (Elliptic Curve Diffie-Hellman)
//    - Senders and receivers can calculate the same shared key without exchanging private keys
//    - Shared key = Sender private key * Receiver public key = Receiver private key * Sender public key
//    - This is a mathematical property of elliptic curve cryptography
//
// 2. ChaCha20-Poly1305
//    - ChaCha20: Stream encryption algorithm, fast and secure
//    - Poly1305: Message authentication code (MAC), ensures message integrity
//    - AEAD (Authenticated Encryption with Associated Data): Simultaneously provides encryption and authentication
//
// 3. Compared to NIP-04
//    - NIP-04 uses AES-256-CBC, known to have padding attack vulnerabilities
//    - NIP-44 uses ChaCha20-Poly1305, more secure and faster
//    - NIP-44 is the new standard recommended by the Nostr community
