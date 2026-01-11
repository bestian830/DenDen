package relay

import (
	"context"
	"fmt"
	"time"

	"github.com/nbd-wtf/go-nostr"
)

// Relay represents a connection to a Nostr relay
type Relay struct {
	*nostr.Relay
	url string
}

// Connect connects to a Nostr relay
// Uses WebSocket protocol to establish connection
//
// Parameters:
//   - relayURL: WebSocket URL of the relay (e.g., "wss://relay.damus.io")
//
// Returns:
//   - *Relay: relay connection object
//   - error: connection error
func Connect(relayURL string) (*Relay, error) {
	fmt.Printf("🔌 Connecting to relay: %s\n", relayURL)

	// Set connection timeout to 5 seconds
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Use go-nostr library to connect to relay
	relay, err := nostr.RelayConnect(ctx, relayURL)
	if err != nil {
		return nil, fmt.Errorf("Connection failed: %w", err)
	}

	fmt.Printf("✅ Connected to relay: %s\n", relayURL)

	return &Relay{
		Relay: relay,
		url:   relayURL,
	}, nil
}

// Publish publishes an Event to the relay
//
// Parameters:
//   - ctx: context (for timeout control)
//   - event: Nostr Event to publish
//
// Returns:
//   - error: publish error
func (r *Relay) Publish(ctx context.Context, event *nostr.Event) error {
	fmt.Printf("\n📤 Publishing Event to relay...\n")
	fmt.Printf("   Event ID: %s\n", event.ID)
	fmt.Printf("   Author: %s\n", event.PubKey[:16]+"...")
	fmt.Printf("   Content: %s\n", event.Content)

	// Publish Event to relay
	err := r.Relay.Publish(ctx, *event)
	if err != nil {
		return fmt.Errorf("Publish failed: %w", err)
	}

	fmt.Printf("✅ Event published successfully!\n")
	return nil
}

// Subscribe subscribes to events that match the given filters
// This function is used to receive messages
//
// Parameters:
//   - ctx: context (for canceling subscription)
//   - filters: filter conditions (e.g., subscribe to all messages from a specific author)
//
// Returns:
//   - chan *nostr.Event: Event receive channel
//   - error: subscription error
func (r *Relay) Subscribe(ctx context.Context, filters []nostr.Filter) (chan *nostr.Event, error) {
	fmt.Printf("\n📥 Subscribing to events...\n")

	// Subscribe to events
	sub, err := r.Relay.Subscribe(ctx, filters)
	if err != nil {
		return nil, fmt.Errorf("Subscription failed: %w", err)
	}

	// Create Event receive channel
	eventChan := make(chan *nostr.Event, 10)

	// Start goroutine to receive Event
	go func() {
		defer close(eventChan)
		for event := range sub.Events {
			eventChan <- event
		}
	}()

	fmt.Printf("✅ Subscription successful!\n")
	return eventChan, nil
}

// Close closes the connection to the relay
func (r *Relay) Close() error {
	fmt.Printf("🔌 Closing connection to relay...\n")
	return r.Relay.Close()
}

// GetURL gets the URL of the relay
func (r *Relay) GetURL() string {
	return r.url
}

// PublicRelays returns a list of some public Nostr relays
func PublicRelays() []string {
	return []string{
		"wss://relay.damus.io",     // Damus official relay
		"wss://nos.lol",            // nos.lol relay
		"wss://relay.nostr.band",   // Nostr Band relay
		"wss://nostr.wine",         // Wine relay
		"wss://relay.snort.social", // Snort relay
	}
}
