package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"strings"

	"denden-core/internal/client"
)

func main() {
	fmt.Println("🔥🔥🔥 Den Den CLI - Phase 1.5 🔥🔥🔥")
	fmt.Println("================================================")
	fmt.Println("Decentralized Encrypted Messenger")
	fmt.Println("================================================\n")

	// Initialize client
	fmt.Println("🔧 Initializing client...")
	c, err := client.NewClient("")
	if err != nil {
		log.Fatalf("❌ Failed to initialize client: %v", err)
	}
	defer c.Close()

	// Display identity
	identity := c.GetIdentity()
	fmt.Printf("\n🆔 Your Identity:\n")
	fmt.Printf("   npub: %s\n", identity.Npub)
	fmt.Printf("   Public key: %s\n", identity.PublicKey[:16]+"...")

	// Connect to relay
	fmt.Println("\n🔌 Connecting to relay...")
	relayURL := "wss://relay.damus.io"
	err = c.Connect(relayURL)
	if err != nil {
		log.Fatalf("❌ Failed to connect to relay: %v", err)
	}

	// Start listening for messages
	err = c.StartListening()
	if err != nil {
		log.Fatalf("❌ Failed to start listening: %v", err)
	}

	// Print help
	printHelp()

	// Main command loop
	scanner := bufio.NewScanner(os.Stdin)
	fmt.Print("\n> ")

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		if line == "" {
			fmt.Print("> ")
			continue
		}

		// Handle command
		if !handleCommand(c, line) {
			break // Exit if command returns false
		}

		fmt.Print("> ")
	}

	if err := scanner.Err(); err != nil {
		log.Printf("❌ Error reading input: %v", err)
	}

	fmt.Println("\n👋 Goodbye!")
}

// handleCommand processes a user command
// Returns false if the program should exit
func handleCommand(c *client.Client, line string) bool {
	parts := strings.Fields(line)
	if len(parts) == 0 {
		return true
	}

	command := parts[0]

	switch command {
	case "/send":
		if len(parts) < 3 {
			fmt.Println("❌ Usage: /send <npub|pubkey> <message>")
			fmt.Println("   Example: /send npub1abc... Hello there!")
			return true
		}

		recipientPubKey := parts[1]
		message := strings.Join(parts[2:], " ")

		fmt.Printf("📤 Sending message to %s...\n", recipientPubKey[:12]+"...")
		err := c.SendEncryptedMessage(recipientPubKey, message)
		if err != nil {
			fmt.Printf("❌ Failed to send message: %v\n", err)
		} else {
			fmt.Println("✅ Message sent!")
		}

	case "/info":
		identity := c.GetIdentity()
		fmt.Println("\n🆔 Your Identity:")
		fmt.Printf("   npub: %s\n", identity.Npub)
		fmt.Printf("   nsec: %s (keep this secret!)\n", identity.Nsec)
		fmt.Printf("   Public key (hex): %s\n", identity.PublicKey)
		fmt.Printf("   Private key (hex): %s... (keep this secret!)\n", identity.PrivateKey[:16])

	case "/help":
		printHelp()

	case "/quit", "/exit", "/q":
		return false

	default:
		if strings.HasPrefix(command, "/") {
			fmt.Printf("❌ Unknown command: %s\n", command)
			fmt.Println("   Type /help for available commands")
		} else {
			fmt.Println("❌ Commands must start with /")
			fmt.Println("   Type /help for available commands")
		}
	}

	return true
}

// printHelp prints available commands
func printHelp() {
	fmt.Println("\n📖 Available Commands:")
	fmt.Println("   /send <npub|pubkey> <message>  Send encrypted message")
	fmt.Println("   /info                           Show your identity")
	fmt.Println("   /help                           Show this help")
	fmt.Println("   /quit or /exit                  Exit the program")
}
