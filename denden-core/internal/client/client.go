package client

import (
	"context"
	"fmt"
	"time"

	"denden-core/internal/crypto"
	"denden-core/internal/identity"
	"denden-core/internal/pow"
	"denden-core/internal/relay"

	"github.com/nbd-wtf/go-nostr"
)

// Client represents the Den Den client with identity and relay connection
type Client struct {
	identity *identity.Identity
	relay    *relay.Relay
	ctx      context.Context
	cancel   context.CancelFunc
}

// NewClient creates a new client instance
// Parameters:
//   - identityPath: path to the identity file (use empty string for default)
//
// Returns:
//   - *Client: new client instance
//   - error: error if any
func NewClient(identityPath string) (*Client, error) {
	// Get identity path
	if identityPath == "" {
		var err error
		identityPath, err = identity.GetDefaultIdentityPath()
		if err != nil {
			return nil, fmt.Errorf("failed to get default identity path: %w", err)
		}
	}

	// Load or generate identity
	ident, isNew, err := identity.EnsureIdentity(identityPath)
	if err != nil {
		return nil, fmt.Errorf("failed to ensure identity: %w", err)
	}

	if isNew {
		fmt.Println("🆕 New identity generated and saved!")
	} else {
		fmt.Println("✅ Identity loaded from file")
	}

	// Create context
	ctx, cancel := context.WithCancel(context.Background())

	return &Client{
		identity: ident,
		ctx:      ctx,
		cancel:   cancel,
	}, nil
}

// Connect connects to a Nostr relay
// Parameters:
//   - relayURL: WebSocket URL of the relay (e.g., "wss://relay.damus.io")
//
// Returns:
//   - error: connection error if any
func (c *Client) Connect(relayURL string) error {
	r, err := relay.Connect(relayURL)
	if err != nil {
		return fmt.Errorf("failed to connect to relay: %w", err)
	}

	c.relay = r
	return nil
}

// SendEncryptedMessage sends an encrypted direct message
// Parameters:
//   - recipientPubKey: recipient's public key (hex format or npub)
//   - content: plaintext message content
//
// Returns:
//   - error: send error if any
func (c *Client) SendEncryptedMessage(recipientPubKey, content string) error {
	if c.relay == nil {
		return fmt.Errorf("not connected to any relay")
	}

	// Decode npub if necessary
	if len(recipientPubKey) > 4 && recipientPubKey[:4] == "npub" {
		decoded, err := identity.DecodePublicKey(recipientPubKey)
		if err != nil {
			return fmt.Errorf("failed to decode recipient public key: %w", err)
		}
		recipientPubKey = decoded
	}

	// Encrypt message
	encrypted, err := crypto.Encrypt(content, c.identity.PrivateKey, recipientPubKey)
	if err != nil {
		return fmt.Errorf("failed to encrypt message: %w", err)
	}

	// Create Kind 4 event (Encrypted Direct Message)
	event := &nostr.Event{
		PubKey:    c.identity.PublicKey,
		CreatedAt: nostr.Timestamp(time.Now().Unix()),
		Kind:      4, // Kind 4 = Encrypted Direct Message
		Tags: []nostr.Tag{
			{"p", recipientPubKey}, // Recipient's public key
		},
		Content: encrypted,
	}

	// Mine with PoW
	difficulty := pow.GetDifficultyRecommendation("private")
	_, _, _, err = pow.MineEvent(event, difficulty)
	if err != nil {
		return fmt.Errorf("failed to mine event: %w", err)
	}

	// Sign event
	err = event.Sign(c.identity.PrivateKey)
	if err != nil {
		return fmt.Errorf("failed to sign event: %w", err)
	}

	// Publish to relay
	ctx, cancel := context.WithTimeout(c.ctx, 10*time.Second)
	defer cancel()

	err = c.relay.Publish(ctx, event)
	if err != nil {
		return fmt.Errorf("failed to publish event: %w", err)
	}

	return nil
}

// GetIdentity returns the client's identity
func (c *Client) GetIdentity() *identity.Identity {
	return c.identity
}

// GetRelay returns the relay connection
func (c *Client) GetRelay() *relay.Relay {
	return c.relay
}

// GetContext returns the client's context
func (c *Client) GetContext() context.Context {
	return c.ctx
}

// Close closes the client and cleans up resources
func (c *Client) Close() error {
	c.cancel() // Cancel context

	if c.relay != nil {
		return c.relay.Close()
	}

	return nil
}
