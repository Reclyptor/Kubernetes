#!/bin/bash
# Plain-text override of the image's /home/steam/server/discord.sh, mounted over
# it via ConfigMap. The vendor script only sends embed "cards" (title + colored
# body); this sends the message as plain channel content — no card, no title, no
# color. Interface matches DiscordMessage(): $1=title (unused) $2=message
# $3=level (unused) $4=enabled $5=webhook_url. If a future image bump changes
# discord.sh, re-diff this against it.
# shellcheck source=scripts/helper_functions.sh
source "/home/steam/server/helper_functions.sh"

DEFAULT_CONNECT_TIMEOUT=30
DEFAULT_MAX_TIMEOUT=30
DISCORD_FLAGS=0

MESSAGE=$2
ENABLED=$4
URL=$5

# Preserve the image's silent (@silent) behavior driven by the env var.
if [ "$DISCORD_SUPPRESS_NOTIFICATIONS" = true ]; then
    DISCORD_FLAGS=4096
fi

if [ -n "${DISCORD_CONNECT_TIMEOUT}" ] && [[ "${DISCORD_CONNECT_TIMEOUT}" =~ ^[0-9]+$ ]]; then
    CONNECT_TIMEOUT=$DISCORD_CONNECT_TIMEOUT
else
    CONNECT_TIMEOUT=$DEFAULT_CONNECT_TIMEOUT
fi

if [ -n "${DISCORD_MAX_TIMEOUT}" ] && [[ "${DISCORD_MAX_TIMEOUT}" =~ ^[0-9]+$ ]]; then
    MAX_TIMEOUT=$DISCORD_MAX_TIMEOUT
else
    MAX_TIMEOUT=$DEFAULT_MAX_TIMEOUT
fi

if [ "${ENABLED,,}" = true ]; then
    if [ "$URL" == "" ]; then
        DISCORD_URL="$DISCORD_WEBHOOK_URL"
    else
        DISCORD_URL="$URL"
    fi
    # Escape with backslash to prevent strings starting with @, %, : from being interpreted as filenames or stdin
    JSON=$(jo content="\\$MESSAGE" flags="$DISCORD_FLAGS")
    LogInfo "Sending Discord json: ${JSON}"
    curl -sfSL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIMEOUT" -H "Content-Type: application/json" -d "$JSON" "$DISCORD_URL"
fi
