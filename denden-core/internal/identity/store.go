package identity

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Identity represents a user's identity including all key formats
type Identity struct {
	PrivateKey string `json:"private_key"` // Private key in hex format
	PublicKey  string `json:"public_key"`  // Public key in hex format
	Nsec       string `json:"nsec"`        // Private key in Bech32 format (nsec1...)
	Npub       string `json:"npub"`        // Public key in Bech32 format (npub1...)
}

// SaveIdentity saves the identity to a JSON file
// Parameters:
//   - identity: the identity to save
//   - filePath: path to the JSON file
func SaveIdentity(identity *Identity, filePath string) error {
	// Create directory if it doesn't exist
	// Use filepath.Dir() to safely extract directory path (cross-platform)
	dir := filepath.Dir(filePath)
	if dir != "" && dir != "." {
		err := os.MkdirAll(dir, 0700) // 0700 = only owner can read/write
		if err != nil {
			return fmt.Errorf("failed to create directory: %w", err)
		}
	}

	// Marshal identity to JSON
	data, err := json.MarshalIndent(identity, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal identity: %w", err)
	}

	// Write to file with restricted permissions (only owner can read)
	err = os.WriteFile(filePath, data, 0600)
	if err != nil {
		return fmt.Errorf("failed to write identity file: %w", err)
	}

	return nil
}

// LoadIdentity loads the identity from a JSON file
// Parameters:
//   - filePath: path to the JSON file
//
// Returns:
//   - *Identity: loaded identity
//   - error: error if file doesn't exist or is invalid
func LoadIdentity(filePath string) (*Identity, error) {
	// Read file
	data, err := os.ReadFile(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("identity file does not exist: %s", filePath)
		}
		return nil, fmt.Errorf("failed to read identity file: %w", err)
	}

	// Unmarshal JSON
	var identity Identity
	err = json.Unmarshal(data, &identity)
	if err != nil {
		return nil, fmt.Errorf("failed to parse identity file: %w", err)
	}

	return &identity, nil
}

// EnsureIdentity ensures an identity exists at the given path
// If the file doesn't exist, generates a new identity and saves it
// If the file exists, loads and returns it
//
// Parameters:
//   - filePath: path to the identity file
//
// Returns:
//   - *Identity: loaded or newly generated identity
//   - bool: true if newly created, false if loaded from file
//   - error: error if any
func EnsureIdentity(filePath string) (*Identity, bool, error) {
	// Try to load existing identity
	identity, err := LoadIdentity(filePath)
	if err == nil {
		// Identity exists, return it
		return identity, false, nil
	}

	// Check if it's a "not exist" error
	if !os.IsNotExist(err) && err.Error() != fmt.Sprintf("identity file does not exist: %s", filePath) {
		// Some other error occurred
		return nil, false, fmt.Errorf("failed to load identity: %w", err)
	}

	// Identity doesn't exist, generate a new one
	privKey, pubKey, nsec, npub, err := GenerateKeyPair()
	if err != nil {
		return nil, false, fmt.Errorf("failed to generate key pair: %w", err)
	}

	identity = &Identity{
		PrivateKey: privKey,
		PublicKey:  pubKey,
		Nsec:       nsec,
		Npub:       npub,
	}

	// Save to file
	err = SaveIdentity(identity, filePath)
	if err != nil {
		return nil, false, fmt.Errorf("failed to save identity: %w", err)
	}

	return identity, true, nil
}

// GetDefaultIdentityPath returns the default path for identity storage
// Returns: ~/.denden/identity.json
func GetDefaultIdentityPath() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("failed to get home directory: %w", err)
	}

	return filepath.Join(homeDir, ".denden", "identity.json"), nil
}
