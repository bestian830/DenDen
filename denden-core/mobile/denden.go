package mobile

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"sync"
	"time"

	"denden-core/internal/client"
	"denden-core/internal/crypto"

	"github.com/nbd-wtf/go-nostr"
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

// StartListening starts listening for incoming messages
// Listens to both Kind 0 (Metadata) and Kind 1 (Text Notes)
func (d *DenDenClient) StartListening(callback StringCallback) error {
	if d.client.GetRelay() == nil {
		return fmt.Errorf("not connected to relay")
	}

	d.callback = callback

	// Subscribe to Kind 0 (Metadata) and Kind 1 (Text Notes)
	filters := []nostr.Filter{
		{
			Kinds: []int{0, 1}, // Kind 0 = Metadata, Kind 1 = Text Note
			Limit: 20,
		},
	}

	// Subscribe to events
	ctx := context.Background()
	eventChan, err := d.client.GetRelay().Subscribe(ctx, filters)
	if err != nil {
		return fmt.Errorf("subscription failed: %w", err)
	}

	// Start background goroutine to consume events and call callback
	go d.handleIncomingEvents(eventChan)

	return nil
}

// handleIncomingEvents processes incoming events and calls the mobile callback
func (d *DenDenClient) handleIncomingEvents(eventChan chan *nostr.Event) {
	for {
		select {
		case <-d.stopChan:
			return

		case <-d.client.GetContext().Done():
			return

		case event, ok := <-eventChan:
			if !ok {
				return
			}

			d.processEvent(event)
		}
	}
}

// processEvent formats an event and calls the mobile callback
func (d *DenDenClient) processEvent(event *nostr.Event) {
	switch event.Kind {
	case 0:
		// Kind 0: Metadata
		// Parse and cache profile, don't send to Flutter to avoid spam
		d.cacheProfile(event.PubKey, event.Content)

	case 1:
		// Kind 1: Text Note (public post)
		// Enrich with cached profile data
		profile := d.getProfileFromCache(event.PubKey)

		messageJSON := fmt.Sprintf(
			`{"kind":1,"sender":"%s","content":"%s","time":"%s","eventId":"%s","authorName":"%s","avatarUrl":"%s"}`,
			event.PubKey,
			escapeJSON(event.Content),
			event.CreatedAt.Time().Format(time.RFC3339),
			event.ID,
			escapeJSON(profile.Name),
			escapeJSON(profile.Picture),
		)

		if d.callback != nil {
			d.callback.OnMessage(messageJSON)
		}

	case 4:
		// Kind 4: Encrypted Direct Message
		decrypted, err := crypto.Decrypt(
			event.Content,
			d.client.GetIdentity().PrivateKey,
			event.PubKey,
		)
		if err != nil {
			errorJSON := fmt.Sprintf(
				`{"kind":4,"error":"Failed to decrypt message","sender":"%s"}`,
				event.PubKey[:16],
			)
			if d.callback != nil {
				d.callback.OnMessage(errorJSON)
			}
			return
		}

		profile := d.getProfileFromCache(event.PubKey)

		messageJSON := fmt.Sprintf(
			`{"kind":4,"sender":"%s","content":"%s","time":"%s","eventId":"%s","authorName":"%s","avatarUrl":"%s"}`,
			event.PubKey,
			escapeJSON(decrypted),
			event.CreatedAt.Time().Format(time.RFC3339),
			event.ID,
			escapeJSON(profile.Name),
			escapeJSON(profile.Picture),
		)

		if d.callback != nil {
			d.callback.OnMessage(messageJSON)
		}
	}
}

// cacheProfile parses Kind 0 content and stores in cache
func (d *DenDenClient) cacheProfile(pubkey, content string) {
	var profile Profile
	err := json.Unmarshal([]byte(content), &profile)
	if err != nil {
		return // Invalid metadata, skip
	}

	d.cacheMutex.Lock()
	d.profileCache[pubkey] = profile
	d.cacheMutex.Unlock()
}

// getProfileFromCache retrieves profile from cache (thread-safe)
func (d *DenDenClient) getProfileFromCache(pubkey string) Profile {
	d.cacheMutex.RLock()
	defer d.cacheMutex.RUnlock()

	if profile, exists := d.profileCache[pubkey]; exists {
		return profile
	}

	// Return empty profile if not cached
	return Profile{}
}

// GetProfile returns a profile as JSON string
// This allows Flutter to query profiles manually
func (d *DenDenClient) GetProfile(pubkey string) string {
	profile := d.getProfileFromCache(pubkey)

	if profile.Name == "" && profile.Picture == "" {
		// Profile not in cache
		return fmt.Sprintf(`{"pubkey":"%s","cached":false}`, pubkey)
	}

	// Return all 5 profile fields including banner and website
	return fmt.Sprintf(
		`{"pubkey":"%s","cached":true,"name":"%s","picture":"%s","about":"%s","banner":"%s","website":"%s"}`,
		pubkey,
		escapeJSON(profile.Name),
		escapeJSON(profile.Picture),
		escapeJSON(profile.About),
		escapeJSON(profile.Banner),
		escapeJSON(profile.Website),
	)
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

// escapeJSON escapes special characters in a string for JSON
func escapeJSON(s string) string {
	result := ""
	for _, c := range s {
		switch c {
		case '"':
			result += `\"`
		case '\\':
			result += `\\`
		case '\n':
			result += `\n`
		case '\r':
			result += `\r`
		case '\t':
			result += `\t`
		default:
			result += string(c)
		}
	}
	return result
}

// PublishTextNote publishes a public text note (Kind 1)
// tagsJSON is optional - a JSON string like [["g","geohash","City"]]
func (d *DenDenClient) PublishTextNote(content string, tagsJSON string) error {
	if d.client.GetRelay() == nil {
		return fmt.Errorf("not connected to relay")
	}

	// Parse tags if provided
	var tags nostr.Tags
	if tagsJSON != "" {
		var rawTags [][]string
		if err := json.Unmarshal([]byte(tagsJSON), &rawTags); err != nil {
			fmt.Println("Go Backend: Failed to parse tags JSON:", err)
			// Continue without tags rather than failing
		} else {
			fmt.Println("Go Backend: Received tags:", rawTags)
			for _, tag := range rawTags {
				tags = append(tags, tag)
			}
		}
	}

	// 1. Construct the event
	ev := nostr.Event{
		PubKey:    d.client.GetIdentity().PublicKey,
		CreatedAt: nostr.Now(),
		Kind:      1, // Kind 1 = Short Text Note
		Tags:      tags,
		Content:   content,
	}

	// 2. Sign the event
	err := ev.Sign(d.client.GetIdentity().PrivateKey)
	if err != nil {
		return fmt.Errorf("failed to sign event: %w", err)
	}

	// 3. Publish to the currently connected relay
	err = d.client.GetRelay().Publish(context.Background(), &ev)
	if err != nil {
		return fmt.Errorf("failed to publish event: %w", err)
	}

	return nil
}

// PublishMetadata publishes user metadata (Kind 0) to the network
// Accepts a JSON string containing name, about, picture, banner, website
func (d *DenDenClient) PublishMetadata(metadataJson string) error {
	if d.client.GetRelay() == nil {
		return fmt.Errorf("not connected to relay")
	}

	// 1. Parse the metadata JSON
	var metadata Profile
	if err := json.Unmarshal([]byte(metadataJson), &metadata); err != nil {
		return fmt.Errorf("failed to parse metadata JSON: %w", err)
	}

	// 2. Re-marshal to ensure consistent format
	contentBytes, err := json.Marshal(metadata)
	if err != nil {
		return fmt.Errorf("failed to marshal metadata: %w", err)
	}

	// 3. Construct the event
	ev := nostr.Event{
		PubKey:    d.client.GetIdentity().PublicKey,
		CreatedAt: nostr.Now(),
		Kind:      0, // Kind 0 = Metadata
		Tags:      nil,
		Content:   string(contentBytes),
	}

	// 4. Sign the event
	err = ev.Sign(d.client.GetIdentity().PrivateKey)
	if err != nil {
		return fmt.Errorf("failed to sign event: %w", err)
	}

	// 5. Publish to the relay
	err = d.client.GetRelay().Publish(context.Background(), &ev)
	if err != nil {
		return fmt.Errorf("failed to publish metadata: %w", err)
	}

	// 6. Update local cache immediately so UI reflects changes
	d.cacheMutex.Lock()
	d.profileCache[d.client.GetIdentity().PublicKey] = metadata
	d.cacheMutex.Unlock()

	return nil
}
