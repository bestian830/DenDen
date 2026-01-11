// Package mobile provides GoMobile-compatible wrappers for the DenDen client.
// This file contains publishing logic for text notes and metadata.
package mobile

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/nbd-wtf/go-nostr"
)

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
