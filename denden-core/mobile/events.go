// Package mobile provides GoMobile-compatible wrappers for the DenDen client.
// This file contains event listening and processing logic.
package mobile

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"denden-core/internal/crypto"

	"github.com/nbd-wtf/go-nostr"
)

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
