// Package mobile provides GoMobile-compatible wrappers for the DenDen client.
// This file contains reaction logic (like, reply) with Go-managed state.
package mobile

import (
	"context"
	"fmt"
	"time"

	"github.com/nbd-wtf/go-nostr"
)

// LikeResult represents the result of a like/unlike operation
// GoMobile will convert this to a Swift/Kotlin class
type LikeResult struct {
	IsLiked     bool   // true = just liked, false = just unliked
	LikeEventID string // The event ID of the like (empty if unliked)
	PostID      string // The post that was liked/unliked
}

// ToggleLike toggles the like state of a post
// If not liked -> sends Kind 7 (like) and returns IsLiked=true
// If already liked -> sends Kind 5 (delete) and returns IsLiked=false
// Go manages the like state internally, Flutter doesn't need to track IDs
func (d *DenDenClient) ToggleLike(postId string) (*LikeResult, error) {
	if d.client.GetRelay() == nil {
		return nil, fmt.Errorf("not connected to relay")
	}

	// Check if already liked
	d.likeMutex.RLock()
	existingLikeId, isLiked := d.likeCache[postId]
	d.likeMutex.RUnlock()

	if isLiked {
		// Already liked -> Unlike (send Kind 5 deletion)
		err := d.sendUnlike(existingLikeId)
		if err != nil {
			return nil, err
		}

		// Remove from cache
		d.likeMutex.Lock()
		delete(d.likeCache, postId)
		d.likeMutex.Unlock()

		return &LikeResult{
			IsLiked:     false,
			LikeEventID: "",
			PostID:      postId,
		}, nil
	}

	// Not liked -> Like (send Kind 7 reaction)
	likeEventId, err := d.sendLike(postId)
	if err != nil {
		return nil, err
	}

	// Store in cache
	d.likeMutex.Lock()
	d.likeCache[postId] = likeEventId
	d.likeMutex.Unlock()

	return &LikeResult{
		IsLiked:     true,
		LikeEventID: likeEventId,
		PostID:      postId,
	}, nil
}

// sendLike sends a Kind 7 like event and returns the event ID
func (d *DenDenClient) sendLike(postId string) (string, error) {
	ev := nostr.Event{
		PubKey:    d.client.GetIdentity().PublicKey,
		CreatedAt: nostr.Now(),
		Kind:      7, // Kind 7 = Reaction
		Tags: nostr.Tags{
			{"e", postId},
		},
		Content: "+",
	}

	err := ev.Sign(d.client.GetIdentity().PrivateKey)
	if err != nil {
		return "", fmt.Errorf("failed to sign like event: %w", err)
	}

	err = d.client.GetRelay().Publish(context.Background(), &ev)
	if err != nil {
		return "", fmt.Errorf("failed to publish like: %w", err)
	}

	return ev.ID, nil
}

// sendUnlike sends a Kind 5 deletion event
func (d *DenDenClient) sendUnlike(likeEventId string) error {
	ev := nostr.Event{
		PubKey:    d.client.GetIdentity().PublicKey,
		CreatedAt: nostr.Now(),
		Kind:      5, // Kind 5 = Deletion
		Tags: nostr.Tags{
			{"e", likeEventId},
		},
		Content: "unlike",
	}

	err := ev.Sign(d.client.GetIdentity().PrivateKey)
	if err != nil {
		return fmt.Errorf("failed to sign unlike event: %w", err)
	}

	err = d.client.GetRelay().Publish(context.Background(), &ev)
	if err != nil {
		return fmt.Errorf("failed to publish unlike: %w", err)
	}

	return nil
}

// IsPostLiked checks if a post is currently liked (from Go cache)
func (d *DenDenClient) IsPostLiked(postId string) bool {
	d.likeMutex.RLock()
	defer d.likeMutex.RUnlock()
	_, exists := d.likeCache[postId]
	return exists
}

// LikePost is kept for backward compatibility, but ToggleLike is preferred
// Deprecated: Use ToggleLike instead
func (d *DenDenClient) LikePost(eventId string) error {
	_, err := d.ToggleLike(eventId)
	return err
}

// ReplyPost sends a reply (Kind 1 with e tag) to the specified event
// The reply is a regular text note with an 'e' tag referencing the parent
func (d *DenDenClient) ReplyPost(eventId string, content string) error {
	if d.client.GetRelay() == nil {
		return fmt.Errorf("not connected to relay")
	}

	ev := nostr.Event{
		PubKey:    d.client.GetIdentity().PublicKey,
		CreatedAt: nostr.Now(),
		Kind:      1, // Kind 1 = Text Note
		Tags: nostr.Tags{
			{"e", eventId, "", "reply"},
		},
		Content: content,
	}

	err := ev.Sign(d.client.GetIdentity().PrivateKey)
	if err != nil {
		return fmt.Errorf("failed to sign reply event: %w", err)
	}

	err = d.client.GetRelay().Publish(context.Background(), &ev)
	if err != nil {
		return fmt.Errorf("failed to publish reply: %w", err)
	}

	return nil
}

// PostStats represents statistics for a post
// GoMobile will convert this to a Swift/Kotlin class
type PostStats struct {
	PostID      string // The post ID
	LikeCount   int    // Number of likes (Kind 7 reactions)
	ReplyCount  int    // Number of replies (reserved for future)
	IsLikedByMe bool   // Whether the current user has liked this post
}

// GetPostStats queries the relay for post statistics (likes, replies)
// Uses a 3-second timeout for performance
func (d *DenDenClient) GetPostStats(postId string) (*PostStats, error) {
	if d.client.GetRelay() == nil {
		return nil, fmt.Errorf("not connected to relay")
	}

	// Create context with 3-second timeout
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	// Query Kind 7 (reactions) for this post
	filters := []nostr.Filter{
		{
			Kinds: []int{7},
			Tags:  map[string][]string{"e": {postId}},
		},
	}

	eventChan, err := d.client.GetRelay().Subscribe(ctx, filters)
	if err != nil {
		return nil, fmt.Errorf("failed to subscribe for stats: %w", err)
	}

	likeCount := 0
	isLikedByMe := false
	myPubkey := d.client.GetIdentity().PublicKey

	// Collect events until timeout or channel closes
	for {
		select {
		case <-ctx.Done():
			// Timeout reached, return what we have
			return &PostStats{
				PostID:      postId,
				LikeCount:   likeCount,
				ReplyCount:  0,
				IsLikedByMe: isLikedByMe,
			}, nil

		case event, ok := <-eventChan:
			if !ok {
				// Channel closed (EOSE received)
				return &PostStats{
					PostID:      postId,
					LikeCount:   likeCount,
					ReplyCount:  0,
					IsLikedByMe: isLikedByMe,
				}, nil
			}

			// Count this like
			if event.Kind == 7 && event.Content == "+" {
				likeCount++
				if event.PubKey == myPubkey {
					isLikedByMe = true
				}
			}
		}
	}
}
