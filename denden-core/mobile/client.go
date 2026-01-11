// Package mobile provides GoMobile-compatible wrappers for the DenDen client.
// This file contains the core client struct, initialization, and connection logic.
package mobile

import (
	"fmt"
	"path/filepath"
	"sync"

	"denden-core/internal/client"
)

// StringCallback is the interface that mobile platforms must implement
// to receive async messages from the Go backend
type StringCallback interface {
	OnMessage(json string)
}

// Profile represents a user's metadata from Kind 0
type Profile struct {
	Name    string `json:"name"`
	Picture string `json:"picture"`
	About   string `json:"about"`
	Banner  string `json:"banner,omitempty"`
	Website string `json:"website,omitempty"`
}

// DenDenClient is the mobile-friendly wrapper for the Den Den client
// This struct will be exposed to mobile platforms via gomobile
type DenDenClient struct {
	client       *client.Client
	callback     StringCallback
	stopChan     chan struct{}
	seedRelays   []string           // Seed relay pool for Ocean feature
	connectedTo  string             // Currently connected relay
	profileCache map[string]Profile // In-memory cache for user profiles (pubkey -> Profile)
	cacheMutex   sync.RWMutex       // Mutex for thread-safe cache access
	likeCache    map[string]string  // In-memory cache for likes (postId -> likeEventId)
	likeMutex    sync.RWMutex       // Mutex for thread-safe like cache access
}

// Default seed relays for Ocean (public timeline)
var defaultSeedRelays = []string{
	"wss://relay.damus.io",
	"wss://relay.nostr.band",
	"wss://nos.lol",
}

// NewDenDenClient creates a new Den Den client for mobile use
func NewDenDenClient(storageDir string) (*DenDenClient, error) {
	// Create identity file path
	identityPath := filepath.Join(storageDir, "identity.json")

	// Initialize the underlying client
	c, err := client.NewClient(identityPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create client: %w", err)
	}

	return &DenDenClient{
		client:       c,
		stopChan:     make(chan struct{}),
		seedRelays:   defaultSeedRelays,
		profileCache: make(map[string]Profile),
		likeCache:    make(map[string]string),
	}, nil
}

// Connect connects to a specific Nostr relay
func (d *DenDenClient) Connect(relayURL string) error {
	err := d.client.Connect(relayURL)
	if err != nil {
		return fmt.Errorf("connection failed: %w", err)
	}
	d.connectedTo = relayURL
	return nil
}

// ConnectToDefault attempts to connect to one of the default seed relays
func (d *DenDenClient) ConnectToDefault() error {
	var lastErr error

	for _, relayURL := range d.seedRelays {
		err := d.Connect(relayURL)
		if err == nil {
			return nil
		}
		lastErr = err
	}

	if lastErr != nil {
		return fmt.Errorf("failed to connect to any seed relay: %w", lastErr)
	}
	return fmt.Errorf("no seed relays available")
}

// Send sends an encrypted message to a recipient
func (d *DenDenClient) Send(recipientPubKey, content string) error {
	err := d.client.SendEncryptedMessage(recipientPubKey, content)
	if err != nil {
		return fmt.Errorf("send failed: %w", err)
	}
	return nil
}

// GetIdentityJSON returns the user's identity as JSON string
func (d *DenDenClient) GetIdentityJSON() string {
	ident := d.client.GetIdentity()
	return fmt.Sprintf(
		`{"npub":"%s","nsec":"%s","publicKey":"%s","privateKey":"%s"}`,
		ident.Npub,
		ident.Nsec,
		ident.PublicKey,
		ident.PrivateKey,
	)
}

// GetConnectedRelay returns the currently connected relay URL
func (d *DenDenClient) GetConnectedRelay() string {
	return d.connectedTo
}

// Close closes the client and cleans up resources
func (d *DenDenClient) Close() error {
	close(d.stopChan)
	return d.client.Close()
}
