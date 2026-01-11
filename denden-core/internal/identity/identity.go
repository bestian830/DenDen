package identity

import (
	"encoding/hex"
	"fmt"

	"github.com/nbd-wtf/go-nostr"
	"github.com/nbd-wtf/go-nostr/nip19"
)

// GenerateKeyPair generate a key pair according to Nostr standard
// Returns:
//   - privKey: private key in hex string (64 characters)
//   - pubKey: public key in hex string (64 characters)
//   - nsec: private key in Bech32 format (starts with "nsec1")
//   - npub: public key in Bech32 format (starts with "npub1")
func GenerateKeyPair() (privKey, pubKey, nsec, npub string, err error) {
	// generate private key using go-nostr library
	// internal uses secp256k1 elliptic curve encryption algorithm
	sk := nostr.GeneratePrivateKey()

	// derive public key from private key
	// secp256k1's property: public key = private key * G (G is the base point of the elliptic curve)
	pk, err := nostr.GetPublicKey(sk)
	if err != nil {
		return "", "", "", "", fmt.Errorf("failed to get public key: %w", err)
	}

	// encode private key to Bech32 format (nsec)
	// Bech32 is a human-readable encoding format with error detection
	nsecEncoded, err := nip19.EncodePrivateKey(sk)
	if err != nil {
		return "", "", "", "", fmt.Errorf("failed to encode private key: %w", err)
	}

	// encode public key to Bech32 format (npub)
	npubEncoded, err := nip19.EncodePublicKey(pk)
	if err != nil {
		return "", "", "", "", fmt.Errorf("failed to encode public key: %w", err)
	}

	return sk, pk, nsecEncoded, npubEncoded, nil
}

// DecodePrivateKey decode private key from nsec format
func DecodePrivateKey(nsec string) (string, error) {
	prefix, value, err := nip19.Decode(nsec)
	if err != nil {
		return "", fmt.Errorf("failed to decode private key: %w", err)
	}

	if prefix != "nsec" {
		return "", fmt.Errorf("invalid private key format, should start with 'nsec'")
	}

	// value is interface{}, need to assert it to string
	privKey, ok := value.(string)
	if !ok {
		return "", fmt.Errorf("invalid private key format, should be string")
	}

	return privKey, nil
}

// DecodePublicKey decode public key from npub format
func DecodePublicKey(npub string) (string, error) {
	prefix, value, err := nip19.Decode(npub)
	if err != nil {
		return "", fmt.Errorf("failed to decode public key: %w", err)
	}

	if prefix != "npub" {
		return "", fmt.Errorf("invalid public key format, should start with 'npub'")
	}

	pubKey, ok := value.(string)
	if !ok {
		return "", fmt.Errorf("invalid public key format, should be string")
	}

	return pubKey, nil
}

// GetPublicKeyFromPrivate get public key from private key
func GetPublicKeyFromPrivate(privKey string) (string, error) {
	// verify private key format (should be 64 characters)
	if len(privKey) != 64 {
		return "", fmt.Errorf("invalid private key format, should be 64 characters")
	}

	_, err := hex.DecodeString(privKey)
	if err != nil {
		return "", fmt.Errorf("private key is not a valid hex string: %w", err)
	}

	// calculate public key using secp256k1
	pubKey, err := nostr.GetPublicKey(privKey)
	if err != nil {
		return "", fmt.Errorf("failed to get public key from private key: %w", err)
	}

	return pubKey, nil
}
