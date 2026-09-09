#!/usr/bin/env bash
# wow-api-lookup.sh
# Fetches WoW API documentation from warcraft.wiki.gg (default) or from
# Blizzard's own generated API documentation mirrored on townlong-yak.com.
#
# Usage:
#   ./Tools/wow-api-lookup.sh [--source wiki|framexml] <API_name>
#
# Examples:
#   ./Tools/wow-api-lookup.sh C_MythicPlus.GetRunHistory
#   ./Tools/wow-api-lookup.sh C_ChallengeMode.GetMapTable
#   ./Tools/wow-api-lookup.sh CHALLENGE_MODE_MAPS_UPDATE
#   ./Tools/wow-api-lookup.sh CreateFrame
#   ./Tools/wow-api-lookup.sh --source framexml C_MythicPlus.GetRunHistory
#   ./Tools/wow-api-lookup.sh --source framexml C_WeeklyRewards
#
# The framexml source is for verification and edge cases (exact types,
# nullability, defaults, enum values), not for routine lookups — see
# .github/skills/wow-api-lookup/SKILL.md. Never run it in a loop or from CI.

set -euo pipefail

WIKI_BASE="https://warcraft.wiki.gg/wiki"
FRAMEXML_BASE="https://www.townlong-yak.com/framexml/live/Blizzard_APIDocumentationGenerated"
USER_AGENT="MythicPlusTracker-api-lookup (addon development, single on-demand lookup)"

usage() {
    echo "Usage: $0 [--source wiki|framexml] <API_function_or_event>"
    echo ""
    echo "Examples:"
    echo "  $0 C_MythicPlus.GetRunHistory"
    echo "  $0 C_ChallengeMode.GetMapTable"
    echo "  $0 CHALLENGE_MODE_MAPS_UPDATE"
    echo "  $0 CreateFrame"
    echo "  $0 --source framexml C_MythicPlus.GetRunHistory"
    echo "  $0 --source framexml C_WeeklyRewards"
    echo ""
    echo "Sources:"
    echo "  wiki      (default) warcraft.wiki.gg — prose, examples, quirks"
    echo "  framexml  townlong-yak.com — Blizzard's generated definitions,"
    echo "            pinned to the live build. Exact signatures and enums."
    echo ""
    echo "Full API index: $WIKI_BASE/World_of_Warcraft_API"
}

SOURCE="wiki"
QUERY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --source)
            SOURCE="${2-}"
            if [ "$SOURCE" != "wiki" ] && [ "$SOURCE" != "framexml" ]; then
                echo "Unknown source: '${SOURCE}'. Expected 'wiki' or 'framexml'."
                echo ""
                usage
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            QUERY="$1"
            shift
            ;;
    esac
done

if [ -z "$QUERY" ]; then
    usage
    exit 1
fi

if ! command -v curl &>/dev/null; then
    echo "curl not found — install it, or open the documentation in a browser."
    exit 0
fi

# Strips HTML tags and entities, collapses blank lines. Rough but readable.
strip_html() {
    sed 's/<style[^>]*>.*<\/style>//gI' \
        | sed 's/<script[^>]*>.*<\/script>//gI' \
        | sed 's/<[^>]*>//g' \
        | sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g; s/&nbsp;/ /g; s/&#[0-9]*;//g' \
        | sed '/^[[:space:]]*$/d' \
        | sed 's/^[[:space:]]*//'
}

lookup_wiki() {
    # Page titles keep the dots but differ by symbol kind: API functions live
    # under an "API_" prefix (API_C_ChallengeMode.GetMapTable), events do not
    # (CHALLENGE_MODE_MAPS_UPDATE, where the prefixed title 404s). Try the
    # prefix first — the bare title can be a redirect stub with no content.
    local candidates=("API_${QUERY}" "${QUERY}")

    echo "=== WoW API Lookup: $QUERY (warcraft.wiki.gg) ==="
    echo ""

    local url="" code candidate
    for candidate in "${candidates[@]}"; do
        code=$(curl -sL -o /dev/null --max-time 10 -A "$USER_AGENT" \
                    -w '%{http_code}' "${WIKI_BASE}/${candidate}" 2>/dev/null) || code="000"
        if [ "$code" = "200" ]; then
            url="${WIKI_BASE}/${candidate}"
            break
        fi
    done

    if [ -z "$url" ]; then
        echo "Page not found on warcraft.wiki.gg (tried '${QUERY}' and 'API_${QUERY}')."
        echo ""
        echo "Try searching: https://warcraft.wiki.gg/index.php?search=${QUERY}"
        echo "Or Blizzard's own definitions: $0 --source framexml ${QUERY}"
        exit 0
    fi

    echo "URL: $url"
    echo ""

    local raw
    raw=$(curl -sL --max-time 10 -A "$USER_AGENT" "$url" 2>/dev/null) || {
        echo "Could not fetch page (network error)."
        echo "Open: $url"
        exit 0
    }

    # MediaWiki wraps the article in mw-parser-output and ends it at
    # printfooter. Everything outside that is chrome and inline scripts, which
    # survive tag stripping and would bury the signature.
    echo "$raw" \
        | sed -n '/mw-parser-output/,/printfooter/p' \
        | strip_html \
        | sed -e '/NewPP limit report/,$d' -e '/^<!--/d' \
        | head -80

    echo ""
    echo "Full page: $url"
}

lookup_framexml() {
    local namespace="${QUERY%%.*}"
    local member=""
    case "$QUERY" in
        *.*) member="${QUERY#*.}" ;;
    esac

    # Blizzard's file names mostly follow the namespace, but not always.
    # Add exceptions here as "C_Namespace:FileName.lua" if one falls out of
    # the candidate scheme below.
    local overrides=""

    local base="${namespace#C_}"
    local candidates=()

    local override
    for override in $overrides; do
        if [ "${override%%:*}" = "$namespace" ]; then
            candidates+=("${override#*:}")
        fi
    done
    candidates+=("${base}Documentation.lua" \
                 "${base}InfoDocumentation.lua" \
                 "${base}ConstantsDocumentation.lua")

    echo "=== WoW API Lookup: $QUERY (townlong-yak, live build) ==="
    echo ""

    local found_url=""
    local tried=""
    local candidate url code
    for candidate in "${candidates[@]}"; do
        url="${FRAMEXML_BASE}/${candidate}"
        code=$(curl -s -o /dev/null --max-time 10 -A "$USER_AGENT" \
                    -w '%{http_code}' "$url" 2>/dev/null) || code="000"
        tried="${tried}  ${code}  ${url}"$'\n'
        if [ "$code" = "200" ]; then
            found_url="$url"
            break
        fi
    done

    if [ -z "$found_url" ]; then
        echo "No generated documentation file found for namespace '${namespace}'."
        echo ""
        echo "Tried:"
        printf '%s' "$tried"
        echo "Directory listings are not available (they return 404) — the exact"
        echo "file name has to be known. Check the build index by hand:"
        echo "  https://www.townlong-yak.com/framexml/live"
        exit 0
    fi

    echo "URL: $found_url"
    echo ""

    local raw text
    raw=$(curl -sL --max-time 10 -A "$USER_AGENT" "$found_url" 2>/dev/null) || {
        echo "Could not fetch page (network error)."
        echo "Open: $found_url"
        exit 0
    }
    text=$(echo "$raw" | strip_html)

    if [ -n "$member" ]; then
        # Each documented symbol starts with a Name = "..." line; print that
        # one, then stop where the next symbol begins.
        local block
        block=$(echo "$text" \
                | grep -A 40 "Name = \"${member}\"" \
                | awk 'NR == 1 { print; next } /^Name = "/ { exit } { print }' \
                | sed -e 's/^},$//' -e '/^{\?$/d' || true)
        if [ -z "$block" ]; then
            echo "'${member}' not found in this file. Symbols it does document:"
            echo ""
            echo "$text" | grep -o 'Name = "[A-Za-z0-9_]*"' | sed 's/Name = /  /' | sort -u
        else
            echo "$block"
        fi
    else
        echo "Symbols documented in this file:"
        echo ""
        echo "$text" | grep -o 'Name = "[A-Za-z0-9_]*"' | sed 's/Name = /  /' | sort -u
    fi

    echo ""
    echo "Full file: $found_url"
}

if [ "$SOURCE" = "framexml" ]; then
    lookup_framexml
else
    lookup_wiki
fi
