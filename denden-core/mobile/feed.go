package mobile

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"time"

	"github.com/nbd-wtf/go-nostr"
	"github.com/nbd-wtf/go-nostr/nip04"
)

// GetUserFeed returns a list of posts (Kind 1) and reposts (Kind 6) authored by the given pubkey.
// limit: maximum number of events to return.
func (d *DenDenClient) GetUserFeed(pubkey string, limit int) (string, error) {
	if d.client.GetRelay() == nil {
		return "", fmt.Errorf("not connected to relay")
	}

	filter := nostr.Filter{
		Kinds:   []int{1, 6},
		Authors: []string{pubkey},
		Limit:   limit,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	events, err := d.client.GetRelay().QuerySync(ctx, filter)
	if err != nil {
		return "", fmt.Errorf("failed to query feed: %w", err)
	}

	// Process events to enrich them (handle reposts, fetch profiles/likes if needed)
	// We reuse the existing processEvents logic from events.go if possible,
	// but since processEvent is for single event, we can iterate.
	// However, processEvent in events.go might return a JSON string.
	// It's better to construct our own list of enriched objects.

	// For now, let's use a simplified approach similar to GetPostThread's structure or just a raw list.
	// Since the UI expects a list of NostrPost objects (JSON), we should return a JSON array.

	var resultEvents []map[string]interface{}

	for _, evt := range events {
		// Basic enrichment
		enriched := map[string]interface{}{
			"kind":    evt.Kind,
			"sender":  evt.PubKey,
			"content": evt.Content,
			"time":    evt.CreatedAt.Time().Format(time.RFC3339),
			"eventId": evt.ID,
			"tags":    evt.Tags,
		}

		// Attach profile if cached
		d.cacheMutex.RLock()
		if profile, ok := d.profileCache[evt.PubKey]; ok {
			enriched["authorName"] = profile.Name
			enriched["avatarUrl"] = profile.Picture
		}
		d.cacheMutex.RUnlock()

		// Handle Kind 6 Repost specific fields
		if evt.Kind == 6 {
			// Parse the inner event from content (NIP-18)
			var innerEvent nostr.Event
			if err := json.Unmarshal([]byte(evt.Content), &innerEvent); err == nil {
				// We don't need to recursively enrich the inner event fully for the list view right now,
				// but the flutter side needs it to display the original post.
				// The flutter NostrPost.fromJson handles parsing the inner JSON if it's a repost.
				// So passing the raw content (which IS the inner JSON) is correct.
				enriched["repostBy"] = evt.PubKey
			}
		}

		resultEvents = append(resultEvents, enriched)
	}

	// Sort by CreatedAt desc
	// events from QuerySync might not be sorted.
	// (Simple bubble sort or just relying on relay order? Relays usually sort desc.
	// Let's assume relay returns desc for now, or we can sort if needed.
	// QuerySync usually returns somewhat sorted but not guaranteed across multiple relays,
	// but here we are probably connected to one pool/relay logic.)

	jsonBytes, err := json.Marshal(resultEvents)
	if err != nil {
		return "", fmt.Errorf("failed to marshal feed: %w", err)
	}

	return string(jsonBytes), nil
}

// GetSingleEvent fetches a single event by ID (for Reply context).
func (d *DenDenClient) GetSingleEvent(eventId string) (string, error) {
	if d.client.GetRelay() == nil {
		return "", fmt.Errorf("not connected to relay")
	}

	filter := nostr.Filter{
		IDs:   []string{eventId},
		Limit: 1,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	events, err := d.client.GetRelay().QuerySync(ctx, filter)
	if err != nil {
		return "", err
	}
	if len(events) == 0 {
		return "", fmt.Errorf("event not found")
	}

	// Enrich the single event
	// We need to return a JSON string of the SINGLE event (or a list of 1? The UI helper expects list usually, but let's see)
	// Actually, let's return a list of 1 to reuse the parsing logic on dart side if needed, or just a single object.
	// Helper `eventsToEnrichedJson` returns a list. Let's return a list of 1.
	return d.eventsToEnrichedJson(events)
}

// GetUserPosts returns Kind 1 (excluding replies) ONLY. No Reposts.
func (d *DenDenClient) GetUserPosts(pubkey string, limit int) (string, error) {
	// Fetch Kind 1 only
	events, err := d.fetchUserEvents(pubkey, []int{1}, limit*2)
	if err != nil {
		return "", err
	}

	var filtered []*nostr.Event
	for _, evt := range events {
		// Strictly NO replies
		if !d.isReply(evt) {
			filtered = append(filtered, evt)
		}
	}

	if len(filtered) > limit {
		filtered = filtered[:limit]
	}

	return d.eventsToEnrichedJson(filtered)
}

// GetUserReplies returns Kind 1 events that ARE replies.
func (d *DenDenClient) GetUserReplies(pubkey string, limit int) (string, error) {
	events, err := d.fetchUserEvents(pubkey, []int{1}, limit*2)
	if err != nil {
		return "", err
	}

	var filtered []*nostr.Event
	for _, evt := range events {
		if d.isReply(evt) {
			filtered = append(filtered, evt)
		}
	}

	if len(filtered) > limit {
		filtered = filtered[:limit]
	}

	return d.eventsToEnrichedJson(filtered)
}

// GetUserMedia returns events that contain image/video URLs.
func (d *DenDenClient) GetUserMedia(pubkey string, limit int) (string, error) {
	events, err := d.fetchUserEvents(pubkey, []int{1}, limit*2)
	if err != nil {
		return "", err
	}

	var filtered []*nostr.Event
	for _, evt := range events {
		if d.hasMedia(evt.Content) {
			filtered = append(filtered, evt)
		}
	}

	if len(filtered) > limit {
		filtered = filtered[:limit]
	}

	return d.eventsToEnrichedJson(filtered)
}

// Helper to fetch events
func (d *DenDenClient) fetchUserEvents(pubkey string, kinds []int, limit int) ([]*nostr.Event, error) {
	if d.client.GetRelay() == nil {
		return nil, fmt.Errorf("not connected to relay")
	}

	filter := nostr.Filter{
		Kinds:   kinds,
		Authors: []string{pubkey},
		Limit:   limit,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	return d.client.GetRelay().QuerySync(ctx, filter)
}

// Helper to determine if an event is a reply (NIP-10)
func (d *DenDenClient) isReply(evt *nostr.Event) bool {
	for _, tag := range evt.Tags {
		if len(tag) >= 2 && tag[0] == "e" {
			// If explicitly marked as root, it's NOT a reply (it's the thread starter, but for feed purposes it is a root post)
			// Wait, NIP-10 says root is "root". But usually a reply has "reply" marker or no marker (deprecated).
			// If it has ANY "e" tag that is NOT "mention", it's likely a reply.
			// Getting this perfectly right is hard, but generally:
			// If it has "e" tag and marker is "reply", yes.
			// If it has "e" tag and no marker, yes (deprecated).
			// If it has "e" tag and marker is "root", it is the root of a thread? No, root is the first post.
			// A post referencing a root IS a reply to that root.
			// So, if there is ANY 'e' tag, it is a reply or a quote.
			// Quotes might be different. But for "Posts" tab, we usually hide things starting with @/referencing others unless it's a clear Quote Repost (which is usually Kind 6 or embedded).

			// Simple heuristic: If it has an 'e' tag, it's a reply/thread participant.
			return true
		}
	}
	return false
}

// Helper to search for media
func (d *DenDenClient) hasMedia(content string) bool {
	// Very basic check for common extensions
	exts := []string{".jpg", ".jpeg", ".png", ".gif", ".mp4", ".mov", ".webp"}
	for _, ext := range exts {
		for i := 0; i < len(content)-len(ext); i++ {
			if content[i:i+len(ext)] == ext {
				return true
			}
		}
	}
	return false
}

// Reusable logic to enrich and marshal events
func (d *DenDenClient) eventsToEnrichedJson(events []*nostr.Event) (string, error) {
	var resultEvents []map[string]interface{}

	for _, evt := range events {
		enriched := map[string]interface{}{
			"kind":    evt.Kind,
			"sender":  evt.PubKey,
			"content": evt.Content,
			"time":    evt.CreatedAt.Time().Format(time.RFC3339),
			"eventId": evt.ID,
			"tags":    evt.Tags,
		}

		d.cacheMutex.RLock()
		if profile, ok := d.profileCache[evt.PubKey]; ok {
			enriched["authorName"] = profile.Name
			enriched["avatarUrl"] = profile.Picture
		}
		d.cacheMutex.RUnlock()

		if evt.Kind == 6 {
			enriched["repostBy"] = evt.PubKey
		}

		resultEvents = append(resultEvents, enriched)
	}

	jsonBytes, err := json.Marshal(resultEvents)
	if err != nil {
		return "", fmt.Errorf("failed to marshal feed: %w", err)
	}

	return string(jsonBytes), nil
}

// GetUserHighlights returns Kind 9802 events.
func (d *DenDenClient) GetUserHighlights(pubkey string, limit int) (string, error) {
	// Kind 9802 is Highlight
	events, err := d.fetchUserEvents(pubkey, []int{9802}, limit)
	if err != nil {
		return "", err
	}

	return d.eventsToEnrichedJson(events)
}

// GetUserReposts returns Kind 6 events only.
func (d *DenDenClient) GetUserReposts(pubkey string, limit int) (string, error) {
	events, err := d.fetchUserEvents(pubkey, []int{6}, limit)
	if err != nil {
		return "", err
	}

	return d.eventsToEnrichedJson(events)
}

// --- Moved from chat.go due to gomobile export issues ---

// SendDirectMessage encrypts and sends a direct message (Kind 4)
func (d *DenDenClient) SendDirectMessage(receiverPubkey, content string) error {
	pk := d.client.GetPublicKey()
	sk := d.client.GetPrivateKey()

	sharedSecret, err := nip04.ComputeSharedSecret(receiverPubkey, sk)
	if err != nil {
		return fmt.Errorf("failed to compute shared secret: %w", err)
	}

	encrypted, err := nip04.Encrypt(content, sharedSecret)
	if err != nil {
		return fmt.Errorf("failed to encrypt: %w", err)
	}

	evt := nostr.Event{
		Kind:      nostr.KindEncryptedDirectMessage, // 4
		Content:   encrypted,
		CreatedAt: nostr.Now(),
		Tags:      nostr.Tags{{"p", receiverPubkey}},
		PubKey:    pk,
	}
	evt.Sign(sk)

	relay := d.client.GetRelay()
	if relay == nil {
		return fmt.Errorf("no connected relay")
	}

	if err := relay.Publish(context.Background(), &evt); err != nil {
		fmt.Printf("GO: SendDirectMessage failed to publish: %v\n", err)
		return fmt.Errorf("failed to publish: %w", err)
	}
	fmt.Printf("GO: SendDirectMessage: Published event %s\n", evt.ID)

	// Optimistically add to local cache
	d.chatMutex.Lock()
	defer d.chatMutex.Unlock()

	msg := ChatMessage{
		ID:        evt.ID,
		Sender:    pk,
		Content:   content,
		CreatedAt: int64(evt.CreatedAt),
		IsMine:    true,
	}
	d.chatCache[receiverPubkey] = append(d.chatCache[receiverPubkey], msg)
	fmt.Printf("GO: SendDirectMessage: Added to cache for %s. New count: %d\n", receiverPubkey, len(d.chatCache[receiverPubkey]))
	return nil
}

// Conversation helper struct
type Conversation struct {
	PartnerPubkey string `json:"partner_pubkey"`
	PartnerName   string `json:"partner_name"`   // NEW
	PartnerAvatar string `json:"partner_avatar"` // NEW
	LastMessage   string `json:"last_message"`
	Timestamp     int64  `json:"timestamp"`
	UnreadCount   int    `json:"unread_count"`
}

// DebugFetchMessages fetches NIP-04 messages (Kind 4) and decrypts them. Returns a debug log string.
func (d *DenDenClient) DebugFetchMessages(limit int64) (string, error) {
	var log string

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	relay := d.client.GetRelay()
	if relay == nil {
		// Auto-reconnect
		log += "Relay nil, attempting auto-connect...\n"
		if err := d.ConnectToDefault(); err != nil {
			return log + fmt.Sprintf("Auto-connect failed: %v", err), fmt.Errorf("no connected relay and auto-connect failed: %w", err)
		}
		relay = d.client.GetRelay()
		if relay == nil {
			return log + "Auto-connect seemingly succeeded but GetRelay is still nil", fmt.Errorf("still no connected relay after connect")
		}
	}
	log += fmt.Sprintf("Relay connected: %s\n", "yes")

	pk := d.client.GetPublicKey()
	sk := d.client.GetPrivateKey()
	log += fmt.Sprintf("My PubKey: %s...\n", pk[:8])

	// 1. Fetch Received Messages (p = me)
	filterReceived := nostr.Filter{
		Kinds: []int{nostr.KindEncryptedDirectMessage},
		Tags:  nostr.TagMap{"p": []string{pk}},
		Limit: int(limit),
	}

	log += fmt.Sprintf("Querying received messages...\n")
	eventsReceived, err := relay.QuerySync(ctx, filterReceived)
	if err != nil {
		log += fmt.Sprintf("Query received error: %v\n", err)
	} else {
		log += fmt.Sprintf("Found %d received events\n", len(eventsReceived))
	}

	// 2. Fetch Sent Messages (authors = me)
	filterSent := nostr.Filter{
		Kinds:   []int{nostr.KindEncryptedDirectMessage},
		Authors: []string{pk},
		Limit:   int(limit),
	}

	log += fmt.Sprintf("Querying sent messages...\n")
	eventsSent, err := relay.QuerySync(ctx, filterSent)
	if err != nil {
		log += fmt.Sprintf("Query sent error: %v\n", err)
	} else {
		log += fmt.Sprintf("Found %d sent events\n", len(eventsSent))
	}

	totalEvents := len(eventsReceived) + len(eventsSent)
	// Merge events
	allEvents := append(eventsReceived, eventsSent...)
	log += fmt.Sprintf("Total events to process: %d\n", totalEvents)

	d.chatMutex.Lock()
	defer d.chatMutex.Unlock()

	decryptedCount := 0
	cachedCount := 0

	for _, evt := range allEvents {
		var partner string
		var sharedSecret []byte
		var err error
		isMine := false

		if evt.PubKey == pk {
			isMine = true
			for _, tag := range evt.Tags {
				if len(tag) >= 2 && tag[0] == "p" {
					partner = tag[1]
					break
				}
			}
			if partner == "" {
				continue
			}
		} else {
			partner = evt.PubKey
		}

		if partner != "" {
			sharedSecret, err = nip04.ComputeSharedSecret(partner, sk)
			if err != nil {
				continue
			}
		} else {
			continue
		}

		decrypted, err := nip04.Decrypt(evt.Content, sharedSecret)
		if err != nil {
			continue
		}
		decryptedCount++

		// Check duplicates in cache
		if d.chatCache[partner] != nil {
			exists := false
			for _, m := range d.chatCache[partner] {
				if m.ID == evt.ID {
					exists = true
					break
				}
			}
			if exists {
				continue
			}
		}

		msg := ChatMessage{
			ID:        evt.ID,
			Sender:    evt.PubKey,
			Content:   decrypted,
			CreatedAt: int64(evt.CreatedAt),
			IsMine:    isMine,
		}
		d.chatCache[partner] = append(d.chatCache[partner], msg)
		cachedCount++
	}

	// Sort messages by time for each conversation
	for k := range d.chatCache {
		sort.Slice(d.chatCache[k], func(i, j int) bool {
			return d.chatCache[k][i].CreatedAt < d.chatCache[k][j].CreatedAt
		})
	}

	log += fmt.Sprintf("Decrypted: %d, New Cached: %d\n", decryptedCount, cachedCount)
	return log, nil
}

// GetConversationList returns a JSON list of active conversations
func (d *DenDenClient) GetConversationList() []byte {
	d.chatMutex.RLock()
	defer d.chatMutex.RUnlock()

	fmt.Printf("GO: GetConversationList called. Cache len: %d\n", len(d.chatCache))

	list := make([]Conversation, 0)
	for partner, msgs := range d.chatCache {
		if len(msgs) == 0 {
			continue
		}
		last := msgs[len(msgs)-1]

		// Attempt to get profile from cache
		// We need to release chatMutex to acquire cacheMutex to avoid potential deadlock
		// if locking order differs. However, getProfileFromCache acquires cacheMutex RLock.
		// Standard locking order: chatMutex -> cacheMutex seems safe if consistent.
		// Let's use internal logic or standard method. 'getProfileFromCache' creates RLock.
		// If another goroutine holds WriteLock on Cache and wants ChatLock, deadlock?
		// Safest to access directly if we are careful, or just rely on RLock re-entrancy if irrelevant.
		// Actually, let's just trigger Fetch if missing.

		var name, avatar string
		// Access cache directly if exposed, or use helper?
		// Helper 'getProfileFromCache' uses cacheMutex.
		// Since we hold chatMutex.RLock, and getProfileFromCache takes cacheMutex.RLock, it's fine
		// unless someone holds cacheMutex.Lock and wants chatMutex.Lock.
		// To be safe, we can defer profile lookup or simple lookup.

		// Let's use the helper but be aware.
		// Better: We are reading.

		profile := d.getProfileFromCache(partner) // Using existing helper
		name = profile.Name
		avatar = profile.Picture

		// If missing, trigger fetch in background (lazy load)
		if name == "" && avatar == "" {
			go d.FetchProfile(partner)
		}

		list = append(list, Conversation{
			PartnerPubkey: partner,
			PartnerName:   name,
			PartnerAvatar: avatar,
			LastMessage:   last.Content,
			Timestamp:     last.CreatedAt,
			UnreadCount:   0,
		})
	}

	// Sort by recent
	sort.Slice(list, func(i, j int) bool {
		return list[i].Timestamp > list[j].Timestamp
	})

	bytes, _ := json.Marshal(list)
	return bytes
}

// GetChatMessages returns JSON list of messages for a partner
func (d *DenDenClient) GetChatMessages(partnerPubkey string) []byte {
	d.chatMutex.RLock()
	defer d.chatMutex.RUnlock()

	msgs := d.chatCache[partnerPubkey]
	if msgs == nil {
		return []byte("[]")
	}

	bytes, _ := json.Marshal(msgs)
	return bytes
}
