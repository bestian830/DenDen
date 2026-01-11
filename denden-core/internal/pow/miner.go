package pow

import (
	"encoding/hex"
	"fmt"
	"math/bits"
	"strconv"
	"time"

	"github.com/nbd-wtf/go-nostr"
)

// MineEvent mines Nostr Event with PoW
// Adheres to NIP-13 standard: Adjust nonce tag to make Event ID satisfy difficulty requirement
//
// Parameters:
//   - event: the Nostr Event to mine (will be modified)
//   - targetDifficulty: target difficulty (number of leading zeros in Event ID)
//
// Returns:
//   - nonce: found nonce value
//   - attempts: number of attempts
//   - duration: mining duration
//   - error: error information
func MineEvent(event *nostr.Event, targetDifficulty int) (int, int, time.Duration, error) {
	fmt.Printf("\n⛏️  Mining PoW... (Target difficulty: %d leading zeros)\n", targetDifficulty)
	start := time.Now()

	nonce := 0
	attempts := 0

	for {
		// 1. Build the nonce tag we want to use
		nonceTag := nostr.Tag{
			"nonce",
			strconv.Itoa(nonce),
			strconv.Itoa(targetDifficulty),
		}

		// 2. Check if there's already a nonce tag in existing Tags
		// IMPORTANT: Don't clear all tags! We need to preserve other tags like:
		//   - ["p", "recipient_pubkey"] for Kind 4 (encrypted DM)
		//   - ["e", "event_id"] for replies
		//   - any other user-defined tags
		found := false
		for i, tag := range event.Tags {
			if len(tag) > 0 && tag[0] == "nonce" {
				// Found it! Replace its value, keep other tags intact
				event.Tags[i] = nonceTag
				found = true
				break
			}
		}

		// 3. If not found (first iteration), append to the end
		if !found {
			event.Tags = append(event.Tags, nonceTag)
		}

		// 2. Calculate Event ID (without signing)
		// Event ID is the SHA256 hash of the serialized Event
		// go-nostr will automatically serialize and calculate ID according to Nostr standard
		// Note: We only calculate ID here, signing will be done AFTER mining succeeds
		event.CreatedAt = nostr.Timestamp(time.Now().Unix())
		event.ID = event.GetID()

		attempts++

		// 3. Check difficulty
		if CheckDifficulty(event.ID, targetDifficulty) {
			duration := time.Since(start)
			fmt.Printf("✅ Mining success!\n")
			fmt.Printf("   Nonce: %d\n", nonce)
			fmt.Printf("   Attempts: %d\n", attempts)
			fmt.Printf("   Duration: %v\n", duration)
			fmt.Printf("   Event ID: %s\n", event.ID)
			return nonce, attempts, duration, nil
		}

		nonce++

		// Print progress every 10000 attempts
		if attempts%10000 == 0 {
			fmt.Printf("   Attempts: %d...\n", attempts)
		}
	}
}

// CheckDifficulty checks if the hash value satisfies the difficulty requirement
// Adheres to NIP-13 standard: checks the number of leading zeros in binary
//
// Parameters:
//   - eventID: Event ID (hex string)
//   - difficulty: required number of leading zeros
//
// Returns:
//   - true: satisfies difficulty requirement
//   - false: does not satisfy difficulty requirement
func CheckDifficulty(eventID string, difficulty int) bool {
	// Decode hex string to byte array
	idBytes, err := hex.DecodeString(eventID)
	if err != nil {
		return false
	}

	// Calculate the number of leading zeros
	leadingZeros := countLeadingZeroBits(idBytes)

	return leadingZeros >= difficulty
}

// countLeadingZeroBits counts the number of leading zeros in a byte array
// This is the core algorithm of NIP-13 standard
func countLeadingZeroBits(data []byte) int {
	count := 0

	// Iterate through each byte
	for _, b := range data {
		if b == 0 {
			// If the entire byte is 0, add 8 leading zeros
			count += 8
		} else {
			// Find the first non-zero byte and calculate its leading zero bits
			// bits.LeadingZeros8 is a function provided by the Go standard library
			count += bits.LeadingZeros8(b)
			break
		}
	}

	return count
}

// GetDifficultyRecommendation recommends difficulty based on message type
// This is the recommended value from Den Den whitepaper
func GetDifficultyRecommendation(messageType string) int {
	switch messageType {
	case "private":
		// Private chat: 8-12 bits (instant on phone)
		return 12
	case "group":
		// Group chat: 12-16 bits (hundreds of milliseconds)
		return 16
	case "public":
		// Public broadcast: 16-20 bits (seconds required)
		return 20
	default:
		return 12
	}
}
