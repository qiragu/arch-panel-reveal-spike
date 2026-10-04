#!/usr/bin/env bash
# Spike S2: seal a review and hand it in as locked comment(s) on the review PR.
# Usage: scripts/seal.sh <plaintext-file> [split-lines]
# The plaintext must carry its own "author:" and "bot:" lines; this script only locks and posts.
set -euo pipefail

TLE="${TLE:-tle}"
REPO="${REPO:-qiragu/arch-panel-reveal-spike}"
cfg() { sed -n "s/^$1: *//p" review.yml; }

plain="$1"
split="${2:-0}"
review=$(cfg review); pr=$(cfg pr); chain=$(cfg chain); round=$(cfg deadline_round)
genesis=$(cfg genesis); period=$(cfg period)
opens=$(date -u -r $((genesis + (round - 1) * period)) +"%Y-%m-%d %H:%M:%S")
login=$(sed -n 's/^author: *//p' "$plain")
bot=$(sed -n 's/^bot: *//p' "$plain")

armor=$(mktemp)
"$TLE" --encrypt ${FORCE:+--force} --chain "$chain" --round "$round" --armor -o "$armor" "$plain"

total=$(wc -l < "$armor" | tr -d ' ')
if [ "$split" -le 0 ] || [ "$split" -ge "$total" ]; then split="$total"; fi
parts=$(( (total + split - 1) / split ))

who="@$login"; [ "$bot" != "none" ] && who="bot $bot, sponsored by @$login"
for i in $(seq 1 "$parts"); do
  chunk=$(sed -n "$(( (i - 1) * split + 1 )),$(( i * split ))p" "$armor")
  body=$(printf '<!-- arch-panel sealed v1 review=%s round=1 bot=%s part=%s/%s -->\n🔒 Sealed review by %s. Opens at %s UTC (drand quicknet round %s). Part %s of %s.\n\n```\n%s\n```\n' \
    "$review" "$bot" "$i" "$parts" "$who" "$opens" "$round" "$i" "$parts" "$chunk")
  gh api "repos/$REPO/issues/$pr/comments" -f body="$body" --jq '.html_url'
done
rm -f "$armor"
