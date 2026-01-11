package client

import (
	"fmt"

	"denden-core/internal/crypto"

	"github.com/nbd-wtf/go-nostr"
)

// StartListening starts a background goroutine to listen for incoming messages
// This will continuously receive messages from the relay and print them to console
func (c *Client) StartListening() error {
	if c.relay == nil {
		return fmt.Errorf("not connected to any relay")
	}

	// Create subscription filter
	// Subscribe to Kind 4 (Encrypted DM) events where we are the recipient
	filters := []nostr.Filter{
		{
			Kinds: []int{4}, // Kind 4 = Encrypted Direct Message
			Tags: nostr.TagMap{
				"p": []string{c.identity.PublicKey}, // Messages sent to us
			},
		},
	}

	// Subscribe to events
	eventChan, err := c.relay.Subscribe(c.ctx, filters)
	if err != nil {
		return fmt.Errorf("failed to subscribe: %w", err)
	}

	// Start background goroutine to handle incoming events
	go c.handleIncomingEvents(eventChan)

	fmt.Println("👂 Listening for messages...")
	return nil
}

// handleIncomingEvents processes incoming events from the subscription
// This runs in a separate goroutine
func (c *Client) handleIncomingEvents(eventChan chan *nostr.Event) {
	for {
		select {
		case <-c.ctx.Done():
			// Context cancelled, stop listening
			return

		case event, ok := <-eventChan:
			if !ok {
				// Channel closed
				return
			}

			// Process the event
			c.processEvent(event)
		}
	}
}

// processEvent processes a single incoming event
func (c *Client) processEvent(event *nostr.Event) {
	// Decrypt the message
	decrypted, err := crypto.Decrypt(event.Content, c.identity.PrivateKey, event.PubKey)
	if err != nil {
		fmt.Printf("⚠️  Failed to decrypt message from %s: %v\n", event.PubKey[:16]+"...", err)
		return
	}

	// Format and print the message
	fmt.Printf("\n📨 New message from %s\n", event.PubKey[:16]+"...")
	fmt.Printf("   Content: %s\n", decrypted)
	fmt.Printf("   Time: %s\n", event.CreatedAt.Time().Format("2006-01-02 15:04:05"))
	fmt.Print("\n> ") // Re-print prompt
}
