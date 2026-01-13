// Package mobile provides GoMobile-compatible wrappers for the DenDen client.
// This file contains thread/comment query APIs for tree-style discussions.
package mobile

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/nbd-wtf/go-nostr"
)

// ThreadEvent represents a single event in a thread
// Used for JSON serialization to Flutter
type ThreadEvent struct {
	EventID   string     `json:"eventId"`
	Sender    string     `json:"sender"`
	Content   string     `json:"content"`
	Time      string     `json:"time"`
	RootID    string     `json:"rootId,omitempty"`    // NIP-10: root event ID
	ReplyToID string     `json:"replyToId,omitempty"` // NIP-10: direct parent ID
	Tags      [][]string `json:"tags,omitempty"`
}

// ThreadResult represents the result of a thread query
type ThreadResult struct {
	RootID string // Root event ID
	Count  int    // Total number of events
	JSON   string // JSON array of ThreadEvent
}

// GetPostThread retrieves all comments under a root post
// Uses NIP-10: all replies include root ID in 'e' tag, so one query gets entire tree
// Timeout: 5 seconds
func (d *DenDenClient) GetPostThread(rootEventId string) (*ThreadResult, error) {
	if d.client.GetRelay() == nil {
		return nil, fmt.Errorf("not connected to relay")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Query Kind 1 events that reference this root ID
	filters := []nostr.Filter{
		{
			Kinds: []int{1},
			Tags:  map[string][]string{"e": {rootEventId}},
			Limit: 100,
		},
	}

	eventChan, err := d.client.GetRelay().Subscribe(ctx, filters)
	if err != nil {
		return nil, fmt.Errorf("failed to subscribe for thread: %w", err)
	}

	var events []ThreadEvent

	for {
		select {
		case <-ctx.Done():
			return d.buildThreadResult(rootEventId, events)

		case event, ok := <-eventChan:
			if !ok {
				return d.buildThreadResult(rootEventId, events)
			}

			if event.Kind == 1 {
				te := d.parseThreadEvent(event)
				events = append(events, te)
			}
		}
	}
}

// GetNotifications retrieves mentions/replies to the current user
// Filter: Kind 1 with #p tag = my pubkey
// Timeout: 5 seconds
func (d *DenDenClient) GetNotifications(limit int) (string, error) {
	if d.client.GetRelay() == nil {
		return "", fmt.Errorf("not connected to relay")
	}

	if limit <= 0 {
		limit = 20
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	myPubkey := d.client.GetIdentity().PublicKey

	filters := []nostr.Filter{
		{
			Kinds: []int{1},
			Tags:  map[string][]string{"p": {myPubkey}},
			Limit: limit,
		},
	}

	eventChan, err := d.client.GetRelay().Subscribe(ctx, filters)
	if err != nil {
		return "", fmt.Errorf("failed to subscribe for notifications: %w", err)
	}

	var events []ThreadEvent

	for {
		select {
		case <-ctx.Done():
			return d.serializeEvents(events)

		case event, ok := <-eventChan:
			if !ok {
				return d.serializeEvents(events)
			}

			if event.Kind == 1 {
				te := d.parseThreadEvent(event)
				events = append(events, te)
			}
		}
	}
}

// parseThreadEvent converts a nostr.Event to ThreadEvent
// Implements NIP-10 parsing for root and reply references
func (d *DenDenClient) parseThreadEvent(event *nostr.Event) ThreadEvent {
	te := ThreadEvent{
		EventID: event.ID,
		Sender:  event.PubKey,
		Content: event.Content,
		Time:    event.CreatedAt.Time().Format(time.RFC3339),
	}

	// Parse tags
	var eTags []string
	for _, tag := range event.Tags {
		if len(tag) >= 2 && tag[0] == "e" {
			eTags = append(eTags, tag[1])

			// NIP-10: Check for explicit markers
			if len(tag) >= 4 {
				marker := tag[3]
				if marker == "root" {
					te.RootID = tag[1]
				} else if marker == "reply" {
					te.ReplyToID = tag[1]
				}
			}
		}
		// Store all tags for reference
		if len(tag) >= 2 {
			te.Tags = append(te.Tags, tag)
		}
	}

	// Fallback: If no explicit markers, use positional (NIP-10 deprecated style)
	// First e tag = root, last e tag = reply (if different)
	if te.RootID == "" && len(eTags) > 0 {
		te.RootID = eTags[0]
	}
	if te.ReplyToID == "" && len(eTags) > 1 {
		te.ReplyToID = eTags[len(eTags)-1]
	}

	return te
}

// buildThreadResult creates a ThreadResult from collected events
func (d *DenDenClient) buildThreadResult(rootEventId string, events []ThreadEvent) (*ThreadResult, error) {
	jsonBytes, err := json.Marshal(events)
	if err != nil {
		return nil, fmt.Errorf("failed to serialize thread events: %w", err)
	}

	return &ThreadResult{
		RootID: rootEventId,
		Count:  len(events),
		JSON:   string(jsonBytes),
	}, nil
}

// serializeEvents converts events to JSON string
func (d *DenDenClient) serializeEvents(events []ThreadEvent) (string, error) {
	jsonBytes, err := json.Marshal(events)
	if err != nil {
		return "", fmt.Errorf("failed to serialize events: %w", err)
	}
	return string(jsonBytes), nil
}
