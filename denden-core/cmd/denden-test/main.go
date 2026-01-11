package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"denden-core/internal/crypto"
	"denden-core/internal/identity"
	"denden-core/internal/pow"
	"denden-core/internal/relay"

	"github.com/nbd-wtf/go-nostr"
)

func main() {
	fmt.Println("🔥🔥🔥 Den Den Core - Phase 1 (Firefly) 🔥🔥🔥")
	fmt.Println("================================================")
	fmt.Println("This is a Nostr standard decentralized messaging system")
	fmt.Println("================================================\n")

	// ==========================================
	// Step 1: Generate Identity
	// ==========================================
	fmt.Println("📝 Step 1: Generate User Identity")
	fmt.Println("------------------------------------------")

	// Generate sender's key pair
	senderPrivKey, senderPubKey, senderNsec, senderNpub, err := identity.GenerateKeyPair()
	if err != nil {
		log.Fatalf("❌ Failed to generate sender's key pair: %v", err)
	}

	fmt.Println("✅ Sender identity generated successfully:")
	fmt.Printf("   Private key (hex):  %s\n", senderPrivKey[:32]+"...")
	fmt.Printf("   Public key (hex):  %s\n", senderPubKey)
	fmt.Printf("   Private key (nsec): %s\n", senderNsec)
	fmt.Printf("   Public key (npub): %s\n", senderNpub)

	// Generate recipient's key pair (for encryption demonstration)
	recipientPrivKey, recipientPubKey, _, recipientNpub, err := identity.GenerateKeyPair()
	if err != nil {
		log.Fatalf("❌ Failed to generate recipient's key pair: %v", err)
	}

	fmt.Println("\n✅ Recipient identity generated successfully:")
	fmt.Printf("   Public key (npub): %s\n", recipientNpub)

	// ==========================================
	// Step 2: End-to-End Encryption (E2E Encryption)
	// ==========================================
	fmt.Println("\n\n📝 Step 2: End-to-End Encryption (NIP-44)")
	fmt.Println("------------------------------------------")

	originalMessage := "Hello World! This is Den Den's first encrypted message 🔒"
	fmt.Printf("Original message: %s\n", originalMessage)

	// Encrypt message
	encryptedMessage, err := crypto.Encrypt(originalMessage, senderPrivKey, recipientPubKey)
	if err != nil {
		log.Fatalf("❌ Failed to encrypt: %v", err)
	}

	fmt.Printf("✅ Encryption successful!\n")
	fmt.Printf("   Ciphertext (first 64 characters): %s...\n", encryptedMessage[:64])

	// Decrypt message
	decryptedMessage, err := crypto.Decrypt(encryptedMessage, recipientPrivKey, senderPubKey)
	if err != nil {
		log.Fatalf("❌ Failed to decrypt: %v", err)
	}

	fmt.Printf("✅ Decryption successful!\n")
	fmt.Printf("   Decrypted message: %s\n", decryptedMessage)

	if originalMessage == decryptedMessage {
		fmt.Println("✅ Encryption/decryption verification passed! ✨")
	}

	// ==========================================
	// Step 3: Create Nostr Event
	// ==========================================
	fmt.Println("\n\n📝 Step 3: Create Nostr Event")
	fmt.Println("------------------------------------------")

	// Create a Text Note Event (Kind 1)
	event := &nostr.Event{
		PubKey:    senderPubKey,
		CreatedAt: nostr.Timestamp(time.Now().Unix()),
		Kind:      1, // Kind 1 = Text Note (public message)
		Tags:      []nostr.Tag{},
		Content:   "Hello Nostr! This is Den Den's first decentralized message! 🚀",
	}

	fmt.Printf("Event type: Kind %d (Text Note)\n", event.Kind)
	fmt.Printf("Content: %s\n", event.Content[:50]+"...")

	// ==========================================
	// Step 4: PoW Mining (Proof of Work)
	// ==========================================
	fmt.Println("\n\n📝 Step 4: PoW Mining (Proof of Work)")
	fmt.Println("------------------------------------------")

	// Set difficulty (lower difficulty for private domain chat demonstration)
	difficulty := pow.GetDifficultyRecommendation("private")
	fmt.Printf("Difficulty: %d leading zeros\n", difficulty)

	// Mine Event
	nonce, attempts, duration, err := pow.MineEvent(event, difficulty)
	if err != nil {
		log.Fatalf("❌ Mining failed: %v", err)
	}

	fmt.Printf("\n✅ Mining statistics:\n")
	fmt.Printf("   Nonce: %d\n", nonce)
	fmt.Printf("   Attempts: %d\n", attempts)
	fmt.Printf("   Duration: %v\n", duration)
	fmt.Printf("   Event ID: %s\n", event.ID)

	// ==========================================
	// Step 5: Sign Event
	// ==========================================
	fmt.Println("\n\n📝 Step 5: Sign Event")
	fmt.Println("------------------------------------------")

	// Sign Event
	err = event.Sign(senderPrivKey)
	if err != nil {
		log.Fatalf("❌ Signature failed: %v", err)
	}

	fmt.Printf("✅ Signature successful!\n")
	fmt.Printf("   Signature (first 32 characters): %s...\n", event.Sig[:32])

	// Verify signature
	isValid, err := event.CheckSignature()
	if err != nil || !isValid {
		log.Fatalf("❌ Signature verification failed: %v", err)
	}

	fmt.Println("✅ Signature verification passed! ✨")

	// ==========================================
	// Step 6: Connect to Relay and Publish Event
	// ==========================================
	fmt.Println("\n\n📝 Step 6: Connect to Nostr Relay and Publish Event")
	fmt.Println("------------------------------------------")

	// Use Damus's public relay
	relayURL := "wss://relay.damus.io"

	r, err := relay.Connect(relayURL)
	if err != nil {
		log.Printf("❌ Failed to connect to relay: %v", err)
		log.Println("⚠️  Skip publishing step (possible network issue)")
	} else {
		defer r.Close()

		// Publish Event
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		err = r.Publish(ctx, event)
		if err != nil {
			log.Printf("❌ Publish Event failed: %v", err)
		} else {
			fmt.Println("\n🎉🎉🎉 Congratulations! Your first Nostr message has been successfully published! 🎉🎉🎉")
			fmt.Printf("You can view this message at https://nostr.band/%s\n", event.ID)
		}
	}

	// ==========================================
	// Summary
	// ==========================================
	fmt.Println("\n\n================================================")
	fmt.Println("✅ Phase 1 (Firefly) All core features demonstrated!")
	fmt.Println("================================================")
	fmt.Println("\nImplemented features:")
	fmt.Println("  ✅ Identity generation (secp256k1 + Bech32)")
	fmt.Println("  ✅ End-to-end encryption (NIP-44)")
	fmt.Println("  ✅ PoW mining (NIP-13)")
	fmt.Println("  ✅ Event signing and verification")
	fmt.Println("  ✅ Relay connection and publishing (WebSocket)")
	fmt.Println("\n🚀 Den Den is ready to move to the next phase!")
}
