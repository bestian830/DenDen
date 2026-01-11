#!/bin/bash

# Test script for Den Den CLI Phase 1.5
# This script demonstrates the basic functionality

echo "================================================"
echo "Den Den Phase 1.5 - Automated Test"
echo "================================================"
echo ""

# Test 1: Check if binary exists
echo "Test 1: Checking if denden-cli binary exists..."
if [ -f "./denden-cli" ]; then
    echo "✅ Binary found"
else
    echo "❌ Binary not found. Building..."
    go build ./cmd/denden-cli
    if [ $? -eq 0 ]; then
        echo "✅ Build successful"
    else
        echo "❌ Build failed"
        exit 1
    fi
fi

echo ""
echo "Test 2: Checking identity persistence..."
echo "First run (will generate new identity)..."
# Run CLI and immediately quit
echo "/quit" | ./denden-cli > /tmp/denden_test1.log 2>&1 &
PID=$!
sleep 3
kill $PID 2>/dev/null || true
wait $PID 2>/dev/null || true

# Check if identity file was created
if [ -f "$HOME/.denden/identity.json" ]; then
    echo "✅ Identity file created at ~/.denden/identity.json"
    NPUB1=$(grep -o '"npub":"npub[^"]*"' "$HOME/.denden/identity.json" | cut -d'"' -f4)
    echo "   First npub: $NPUB1"
else
    echo "❌ Identity file not created"
    exit 1
fi

echo ""
echo "Second run (should load existing identity)..."
echo "/quit" | ./denden-cli > /tmp/denden_test2.log 2>&1 &
PID=$!
sleep 3
kill $PID 2>/dev/null || true
wait $PID 2>/dev/null || true

NPUB2=$(grep -o '"npub":"npub[^"]*"' "$HOME/.denden/identity.json" | cut -d'"' -f4)
echo "   Second npub: $NPUB2"

if [ "$NPUB1" = "$NPUB2" ]; then
    echo "✅ Identity persistence works! (npub matches)"
else
    echo "❌ Identity changed between runs"
    exit 1
fi

echo ""
echo "================================================"
echo "✅ All tests passed!"
echo "================================================"
echo ""
echo "📋 Manual Testing Instructions:"
echo ""
echo "1. Terminal 1 (User A):"
echo "   ./denden-cli"
echo "   Copy your npub from the output"
echo "   Wait for messages..."
echo ""
echo "2. Terminal 2 (User B):"
echo "   DENDEN_IDENTITY_PATH=~/.denden/identity_b.json ./denden-cli"
echo "   /send <User A's npub> Hello from User B!"
echo ""
echo "3. Check Terminal 1:"
echo "   Should see: 📨 New message from ..."
echo ""
