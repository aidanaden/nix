#!/bin/bash
# Send notifications via Telegram
#
# Usage: notify.sh <status> <message>
#   status: success, error, warning, info
#   message: notification text
#
# Setup:
# 1. Create bot via @BotFather on Telegram
# 2. Get your chat ID via @userinfobot
# 3. Set environment variables or edit this file:
#    TELEGRAM_BOT_TOKEN=your_bot_token
#    TELEGRAM_CHAT_ID=your_chat_id

set -euo pipefail

# Configuration - SET THESE!
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# Alternatively, hardcode them here:
# TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
# TELEGRAM_CHAT_ID="123456789"

# Icons for different statuses
declare -A ICONS=(
    ["success"]="✅"
    ["error"]="❌"
    ["warning"]="⚠️"
    ["info"]="ℹ️"
)

usage() {
    echo "Usage: $0 <status> <message>"
    echo "  status: success, error, warning, info"
    echo "  message: notification text"
    exit 1
}

# Check arguments
if [ $# -lt 2 ]; then
    usage
fi

STATUS="${1:-info}"
MESSAGE="${2:-No message provided}"
ICON="${ICONS[$STATUS]:-ℹ️}"
HOSTNAME=$(hostname)

# Check if Telegram is configured
if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "WARNING: Telegram not configured. Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID"
    echo "Message would have been: [$STATUS] $MESSAGE"
    exit 0
fi

# Format message
FORMATTED_MESSAGE="$ICON *[$HOSTNAME]* $STATUS

$MESSAGE

_$(date '+%Y-%m-%d %H:%M:%S')_"

# Send via Telegram API
response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=${FORMATTED_MESSAGE}" \
    -d "parse_mode=Markdown" \
    -d "disable_web_page_preview=true")

# Check response
if echo "$response" | grep -q '"ok":true'; then
    echo "Notification sent successfully"
else
    echo "ERROR: Failed to send notification"
    echo "Response: $response"
    exit 1
fi
