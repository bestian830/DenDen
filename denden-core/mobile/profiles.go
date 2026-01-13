// Package mobile provides GoMobile-compatible wrappers for the DenDen client.
// This file contains profile cache and query logic.
package mobile

import (
	"context"
	"fmt"
	"time"

	"github.com/nbd-wtf/go-nostr"
)

// getProfileFromCache retrieves profile from cache (thread-safe)
func (d *DenDenClient) getProfileFromCache(pubkey string) Profile {
	d.cacheMutex.RLock()
	defer d.cacheMutex.RUnlock()

	if profile, exists := d.profileCache[pubkey]; exists {
		return profile
	}

	return Profile{}
}

// FetchProfile sends a request to fetch metadata for the given pubkey.
// It updates the cache and notifies the frontend via the callback.
func (d *DenDenClient) FetchProfile(pubkey string) {
	if d.client.GetRelay() == nil {
		return
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		filter := nostr.Filter{
			Kinds:   []int{0},
			Authors: []string{pubkey},
			Limit:   1,
		}

		// Use the underlying go-nostr Relay to get access to EndOfStoredEvents
		sub, err := d.client.GetRelay().Relay.Subscribe(ctx, []nostr.Filter{filter})
		if err != nil {
			return
		}

		// We only expect one event (replaceable)
		select {
		case ev := <-sub.Events:
			if ev == nil {
				return
			}
			// Update cache
			d.cacheProfile(ev.PubKey, ev.Content)

			// Notify Flutter
			if d.callback != nil {
				// Construct JSON matching what Flutter HomeFeed expects
				// Flutter checks for "kind":0 and uses "content" (stringified JSON) and "pubkey"
				msg := fmt.Sprintf(`{"kind":0,"pubkey":"%s","content":"%s"}`, ev.PubKey, escapeJSON(ev.Content))
				d.callback.OnMessage(msg)
			}
		case <-ctx.Done():
			// Timeout
		case <-sub.EndOfStoredEvents:
			// No profile found
		}

		sub.Unsub()
	}()
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
