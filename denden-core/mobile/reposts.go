package mobile

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"denden-core/internal/pow"

	"github.com/nbd-wtf/go-nostr"
)

// Repost publishes a repost (Kind 6) of an existing event
// originalEventJson: The full JSON string of the event being reposted (NIP-18 requirement)
func (d *DenDenClient) Repost(originalEventJson string) (string, error) {
	if d.client.GetRelay() == nil {
		return "", fmt.Errorf("not connected to relay")
	}

	// Parse original event to get ID and PubKey
	var originalEvent nostr.Event
	if err := json.Unmarshal([]byte(originalEventJson), &originalEvent); err != nil {
		return "", fmt.Errorf("invalid original event json: %w", err)
	}

	// Create Kind 6 event
	event := &nostr.Event{
		PubKey:    d.client.GetIdentity().PublicKey,
		CreatedAt: nostr.Timestamp(time.Now().Unix()),
		Kind:      6, // Kind 6 = Repost
		Tags: nostr.Tags{
			{"e", originalEvent.ID, d.client.GetRelay().GetURL()},
			{"p", originalEvent.PubKey},
		},
		Content: originalEventJson, // NIP-18: Content should be the stringified JSON of the reposted event
	}

	// Mine and Sign
	difficulty := pow.GetDifficultyRecommendation("public")
	_, _, _, err := pow.MineEvent(event, difficulty)
	if err != nil {
		return "", fmt.Errorf("failed to mine event: %w", err)
	}

	if err := event.Sign(d.client.GetIdentity().PrivateKey); err != nil {
		return "", fmt.Errorf("failed to sign event: %w", err)
	}

	// Publish
	ctx, cancel := context.WithTimeout(d.client.GetContext(), 10*time.Second)
	defer cancel()

	if err := d.client.GetRelay().Publish(ctx, event); err != nil {
		return "", fmt.Errorf("failed to publish repost: %w", err)
	}

	return event.ID, nil
}

// QuotePost publishes a quote repost (Kind 1 with 'q' tag)
// content: The user's commentary
// quotedEventId: The ID of the event being quoted
// authorPubkey: The pubkey of the author of the quoted event
func (d *DenDenClient) QuotePost(content string, quotedEventId string, authorPubkey string) (string, error) {
	if d.client.GetRelay() == nil {
		return "", fmt.Errorf("not connected to relay")
	}

	// Create Kind 1 event
	event := &nostr.Event{
		PubKey:    d.client.GetIdentity().PublicKey,
		CreatedAt: nostr.Timestamp(time.Now().Unix()),
		Kind:      1, // Kind 1 = Text Note
		Tags: nostr.Tags{
			{"q", quotedEventId, d.client.GetRelay().GetURL()}, // 'q' tag for quote
			{"p", authorPubkey}, // 'p' tag for notification
		},
		Content: content,
	}

	// Mine and Sign
	difficulty := pow.GetDifficultyRecommendation("public")
	_, _, _, err := pow.MineEvent(event, difficulty)
	if err != nil {
		return "", fmt.Errorf("failed to mine event: %w", err)
	}

	if err := event.Sign(d.client.GetIdentity().PrivateKey); err != nil {
		return "", fmt.Errorf("failed to sign event: %w", err)
	}

	// Publish
	ctx, cancel := context.WithTimeout(d.client.GetContext(), 10*time.Second)
	defer cancel()

	if err := d.client.GetRelay().Publish(ctx, event); err != nil {
		return "", fmt.Errorf("failed to publish quote: %w", err)
	}

	return event.ID, nil
}
