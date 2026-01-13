package mobile

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/nbd-wtf/go-nostr"
)

// Output: Tree structure where each comment has children
// GetFollowing returns the list of pubkeys that the given user follows (from Kind 3)
func (d *DenDenClient) GetFollowing(pubkey string) string {
	// Query for Kind 3 Contact List
	filter := nostr.Filter{
		Kinds:   []int{3},
		Authors: []string{pubkey},
		Limit:   1,
	}

	// We use the same context as client usually, or background
	// For simplicity in mobile, we use background with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if d.client.GetRelay() == nil {
		return "[]"
	}

	events, err := d.client.GetRelay().QuerySync(ctx, filter)
	if err != nil || len(events) == 0 {
		return "[]"
	}

	// Determine the latest event
	var latest *nostr.Event
	for _, evt := range events {
		if latest == nil || evt.CreatedAt > latest.CreatedAt {
			latest = evt
		}
	}

	if latest == nil {
		return "[]"
	}

	// Extract 'p' tags
	var following []string
	for _, tag := range latest.Tags {
		if len(tag) >= 2 && tag[0] == "p" {
			following = append(following, tag[1])
		}
	}

	jsonBytes, _ := json.Marshal(following)
	return string(jsonBytes)
}

// GetFollowers returns the list of pubkeys that follow the given user (reverse lookup)
func (d *DenDenClient) GetFollowers(pubkey string) string {
	filter := nostr.Filter{
		Kinds: []int{3},
		Tags: map[string][]string{
			"p": {pubkey},
		},
		Limit: 100, // Limit to 100 followers for this mobile demo
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if d.client.GetRelay() == nil {
		return "[]"
	}

	events, err := d.client.GetRelay().QuerySync(ctx, filter)
	if err != nil {
		return "[]"
	}

	var followers []string
	seen := make(map[string]bool)

	for _, evt := range events {
		if !seen[evt.PubKey] {
			followers = append(followers, evt.PubKey)
			seen[evt.PubKey] = true
		}
	}

	jsonBytes, _ := json.Marshal(followers)
	return string(jsonBytes)
}

// Follow adds a pubkey to the current user's contact list (Kind 3)
func (d *DenDenClient) Follow(pubkeyToFollow string) (string, error) {
	if d.client.GetRelay() == nil {
		return "", fmt.Errorf("not connected to relay")
	}

	// 1. Fetch current Kind 3
	myPubkey := d.client.GetIdentity().PublicKey
	filter := nostr.Filter{
		Kinds:   []int{3},
		Authors: []string{myPubkey},
		Limit:   1,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	events, _ := d.client.GetRelay().QuerySync(ctx, filter)

	var currentEvent *nostr.Event
	if len(events) > 0 {
		// Find newest
		for _, evt := range events {
			if currentEvent == nil || evt.CreatedAt > currentEvent.CreatedAt {
				currentEvent = evt
			}
		}
	}

	// 2. Build new tags
	var newTags nostr.Tags
	alreadyFollowing := false

	if currentEvent != nil {
		for _, tag := range currentEvent.Tags {
			if len(tag) >= 2 && tag[0] == "p" {
				if tag[1] == pubkeyToFollow {
					alreadyFollowing = true
				}
				newTags = append(newTags, tag)
			} else {
				// Keep other tags (relays, petnames)
				newTags = append(newTags, tag)
			}
		}
	}

	if alreadyFollowing {
		return "already_following", nil
	}

	// Add new follow
	newTags = append(newTags, nostr.Tag{"p", pubkeyToFollow})

	// 3. Create and Sign new Event
	evt := &nostr.Event{
		Kind:      3,
		PubKey:    myPubkey,
		CreatedAt: nostr.Timestamp(time.Now().Unix()),
		Tags:      newTags,
		Content:   "",
	}

	if currentEvent != nil {
		evt.Content = currentEvent.Content // Preserve relay map if exists
	}

	evt.Sign(d.client.GetIdentity().PrivateKey)

	// 4. Publish
	err := d.client.GetRelay().Publish(ctx, evt)
	if err != nil {
		return "", err
	}

	return "ok", nil
}

// Unfollow removes a pubkey from the current user's contact list
func (d *DenDenClient) Unfollow(pubkeyToUnfollow string) (string, error) {
	if d.client.GetRelay() == nil {
		return "", fmt.Errorf("not connected to relay")
	}

	myPubkey := d.client.GetIdentity().PublicKey
	filter := nostr.Filter{
		Kinds:   []int{3},
		Authors: []string{myPubkey},
		Limit:   1,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	events, _ := d.client.GetRelay().QuerySync(ctx, filter)

	var currentEvent *nostr.Event
	if len(events) > 0 {
		for _, evt := range events {
			if currentEvent == nil || evt.CreatedAt > currentEvent.CreatedAt {
				currentEvent = evt
			}
		}
	}

	if currentEvent == nil {
		return "not_following", nil
	}

	// Filter tags
	var newTags nostr.Tags
	found := false

	for _, tag := range currentEvent.Tags {
		if len(tag) >= 2 && tag[0] == "p" && tag[1] == pubkeyToUnfollow {
			found = true
			continue // Skip this one
		}
		newTags = append(newTags, tag)
	}

	if !found {
		return "not_following", nil
	}

	// Create and Sign
	evt := &nostr.Event{
		Kind:      3,
		PubKey:    myPubkey,
		CreatedAt: nostr.Timestamp(time.Now().Unix()),
		Tags:      newTags,
		Content:   currentEvent.Content,
	}

	evt.Sign(d.client.GetIdentity().PrivateKey)

	// Publish
	err := d.client.GetRelay().Publish(ctx, evt)
	if err != nil {
		return "", err
	}

	return "ok", nil
}
