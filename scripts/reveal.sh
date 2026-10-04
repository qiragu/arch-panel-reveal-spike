#!/usr/bin/env bash
# Spike S2: at the deadline, open every sealed review on the review PR, check it, post it readably, and save
# it to record/round-1/. Safe to run again: it stops if record/round-1/REVEALED exists.
set -uo pipefail

TLE="${TLE:-tle}"
REPO="${REPO:-qiragu/arch-panel-reveal-spike}"
cfg() { sed -n "s/^$1: *//p" review.yml; }
review=$(cfg review); pr=$(cfg pr); chain=$(cfg chain); round=$(cfg deadline_round)
genesis=$(cfg genesis); period=$(cfg period); spec=$(cfg spec_path)
deadline=$((genesis + (round - 1) * period))
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
epoch() { date -u -d "$1" +%s 2>/dev/null || date -u -j -f %Y-%m-%dT%H:%M:%SZ "$1" +%s; }
echo "review=$review pr=$pr deadline_round=$round deadline=$(iso $deadline)"

latest=$(curl -fsS "https://api.drand.sh/$chain/public/latest" | jq -r .round)
if [ "$latest" -lt "$round" ]; then echo "not yet: latest round $latest < $round"; exit 0; fi
mkdir -p record/round-1
if [ -f record/round-1/REVEALED ]; then echo "already revealed"; exit 0; fi

all=$(gh api --paginate "repos/$REPO/issues/$pr/comments" | jq -s 'add // []')
sealed=$(echo "$all" | jq '[.[] | select(.body | contains("<!-- arch-panel sealed v1"))]')
echo "sealed comments found: $(echo "$sealed" | jq length)"

# The body a comment had at the deadline. Unedited comments: the body. Edited after the deadline: the newest
# version from GitHub's edit history that is not later than the deadline (spike: we test what GitHub returns).
body_at_deadline() {
  local id="$1" node="$2" updated="$3" body="$4"
  if [ "$(epoch "$updated")" -le "$deadline" ]; then printf '%s' "$body"; return; fi
  gh api graphql -f id="$node" -f query='query($id:ID!){node(id:$id){... on IssueComment{userContentEdits(first:50){nodes{editedAt diff}}}}}' \
    | jq -r --argjson d "$deadline" '[.data.node.userContentEdits.nodes[] | select((.editedAt|fromdateiso8601) <= $d)] | sort_by(.editedAt) | last | .diff // ""'
}

keys=$(echo "$sealed" | jq -r '.[] | .user.login + "|" + (.body | capture("bot=(?<b>[^ ]+)").b)' | sort -u)
for key in $keys; do
  login="${key%%|*}"; bot="${key##*|}"
  name="$login"; [ "$bot" != "none" ] && name="$login-bot-$bot"
  notes=()
  parts=$(echo "$sealed" | jq --arg l "$login" --arg b "$bot" \
    '[.[] | select(.user.login==$l and (.body|contains("bot="+$b+" ")))] | sort_by(.body | capture("part=(?<p>[0-9]+)/").p | tonumber)')
  n=$(echo "$parts" | jq length)
  want=$(echo "$parts" | jq -r '.[0].body | capture("part=[0-9]+/(?<n>[0-9]+)").n')
  [ "$n" = "$want" ] || notes+=("MISSING PARTS: found $n of $want")
  armor=""; urls=""; last_created=0
  for i in $(seq 0 $((n - 1))); do
    c=$(echo "$parts" | jq ".[$i]")
    id=$(echo "$c" | jq -r .id); node=$(echo "$c" | jq -r .node_id)
    created=$(echo "$c" | jq -r .created_at); updated=$(echo "$c" | jq -r .updated_at)
    urls="$urls $(echo "$c" | jq -r .html_url)"
    ce=$(epoch "$created"); [ "$ce" -gt "$last_created" ] && last_created=$ce
    [ "$ce" -gt "$deadline" ] && notes+=("LATE: part $((i + 1)) posted $created, after the deadline")
    [ "$(epoch "$updated")" -gt "$deadline" ] && notes+=("EDITED AFTER DEADLINE: part $((i + 1)) updated $updated; used the version at the deadline")
    b=$(body_at_deadline "$id" "$node" "$updated" "$(echo "$c" | jq -r .body)")
    chunk=$(printf '%s\n' "$b" | awk '/^```$/{f=!f; next} f')
    armor="$armor$chunk"$'\n'
  done
  plain=$(printf '%s' "$armor" | "$TLE" --decrypt --chain "$chain" 2>&1) || { notes+=("COULD NOT OPEN: $plain"); plain=""; }
  in_author=$(printf '%s\n' "$plain" | sed -n 's/^author: *//p')
  in_bot=$(printf '%s\n' "$plain" | sed -n 's/^bot: *//p')
  in_review=$(printf '%s\n' "$plain" | sed -n 's/^review: *//p')
  [ -n "$plain" ] && [ "$in_author" != "$login" ] && notes+=("AUTHOR MISMATCH: inside says '$in_author', posted by @$login")
  [ -n "$plain" ] && [ "$in_bot" != "$bot" ] && notes+=("BOT MISMATCH: inside says '$in_bot', marker says '$bot'")
  [ -n "$plain" ] && [ "$in_review" != "$review" ] && notes+=("REVIEW MISMATCH: inside says '$in_review'")
  [ ${#notes[@]} -eq 0 ] && notes+=("all checks passed")

  who="@$login"; [ "$bot" != "none" ] && who="bot $bot, sponsored by @$login"
  checks=$(printf -- '- %s\n' "${notes[@]}")
  position=$(printf '%s\n' "$plain" | sed -n 's/^position: *//p')
  reason=$(printf '%s\n' "$plain" | sed -n 's/^reason: *//p')
  looked=$(printf '%s\n' "$plain" | sed -n 's/^looked-at: *//p')
  body=$(printf 'From %s, handed in at %s (deadline %s).\nLocked comment(s):%s\n\n**Position:** %s\n**Reason:** %s\n**Looked at:** %s\n\n**Reveal checks:**\n%s\n' \
    "$who" "$(iso $last_created)" "$(iso $deadline)" "$urls" "$position" "$reason" "$looked" "$checks")
  comments=$(printf '%s\n' "$plain" | sed -n 's/^comment: *//p' | jq -R --arg p "$spec" --arg w "$who" \
    'capture("line=(?<l>[0-9]+) kind=(?<k>[^ ]+) text=(?<t>.*)") | {path:$p, line:(.l|tonumber), side:"RIGHT", body:("**[" + .k + "]** " + .t + "\n\n(from " + $w + ")")}' | jq -s .)
  req=$(jq -n --arg b "$body" --argjson c "$comments" '{event:"COMMENT", body:$b, comments:$c}')
  echo "$key: posting review with $(echo "$comments" | jq length) line comments"
  echo "$req" | gh api "repos/$REPO/pulls/$pr/reviews" --input - --jq '.html_url' || echo "$key: POST FAILED"
  { printf '# Review by %s\n\n%s\n\n## Opened text\n\n```\n%s\n```\n' "$who" "$checks" "$plain"; } > "record/round-1/$name.md"
done

date -u +%Y-%m-%dT%H:%M:%SZ > record/round-1/REVEALED
echo "revealed"
