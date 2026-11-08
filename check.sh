#!/usr/bin/env bash
# outside-heartbeat: runs on a GitHub-hosted runner (outside our Mac Mini and our VPS) every 10 min.
# Opens ONE issue when both are down, closes it when either answers. See README.md.
set -uo pipefail
REPO="${REPO:?REPO not set}"
DRILL="${DRILL:-none}"          # none | both-down (opens a [drill] issue, nobody assigned, run stays green)
STALE="${MINI_STALE_SECS:-1800}" # the Mini writes MINI_BEAT every 10 min; 30 min = three missed beats
ASSIGNEE="${ALERT_ASSIGNEE:-ajgins}"
RETRY_SECS="${RETRY_SECS:-90}"
LABEL=both-down
NOW=$(date +%s)
TARGETS="${TARGETS:-targets.txt}"

vps_up() {
  local u code
  while read -r u; do
    case "$u" in ''|\#*) continue;; esac
    code=$(curl -sS -o /dev/null -m 15 -w '%{http_code}' "$u" 2>/dev/null) || code=000
    if [ "$code" != 000 ] && [ "$code" -lt 500 ]; then return 0; fi
  done < "$TARGETS"
  return 1
}

if vps_up; then vps=up; else sleep "$RETRY_SECS"; if vps_up; then vps=up; else vps=down; fi; fi
if [[ "${MINI_BEAT:-}" =~ ^[0-9]+$ ]] && [ $((NOW - MINI_BEAT)) -le "$STALE" ]; then beat=fresh; else beat=stale; fi
mini=up; [ "$beat" = stale ] && mini=down   # a broken beat writer is caught on the Mini (outside-beat alerts after 3 failed writes)
both=0; [ "$vps" = down ] && [ "$mini" = down ] && both=1
drill=0; [ "$DRILL" = both-down ] && { both=1; drill=1; }
echo "vps=$vps mini_beat=$beat both_down=$both drill=$drill"

gh label create "$LABEL" -R "$REPO" --color B60205 --description "Mini and VPS both unreachable from outside" >/dev/null 2>&1 || true
open=$(gh issue list -R "$REPO" --label "$LABEL" --state open --json number,title,createdAt \
        -q '.[] | "\(.number)\t\(.createdAt)\t\(.title)"' 2>/dev/null || true)
stamp=$(date -u +%Y-%m-%dT%H:%MZ)

if [ "$both" = 1 ]; then
  if [ -n "$open" ]; then echo "still down; issue #$(echo "$open" | head -1 | cut -f1) already open"; exit 0; fi
  if [ "$drill" = 1 ]; then
    gh issue create -R "$REPO" --label "$LABEL" --title "[drill] Both hosts unreachable from outside" \
      --body "Drill at $stamp (workflow_dispatch drill=both-down). Nobody assigned. The next normal run closes it, proving the recovery path." >/dev/null
    echo "drill issue opened"; exit 0
  fi
  gh issue create -R "$REPO" --label "$LABEL" --assignee "$ASSIGNEE" \
    --title "Both hosts unreachable from outside (VPS + Mac Mini)" \
    --body "@$ASSIGNEE outside heartbeat at $stamp: every VPS probe failed twice, ${RETRY_SECS}s apart, and the Mac Mini's heartbeat is over $((STALE / 60)) min old.

Nothing inside us can alert while both are down. Rebuild runbook: agent-review repo, vps-rebuild-runbook.md. This issue closes itself when either host answers." >/dev/null
  echo "ALERT issue opened"; exit 1   # a failed run also sends GitHub's run-failed email
fi

if [ -n "$open" ]; then
  echo "$open" | while IFS=$'\t' read -r n created title; do
    gh issue comment "$n" -R "$REPO" --body "Recovered at $stamp (vps=$vps, mini=$mini). Open since $created." >/dev/null
    gh issue close "$n" -R "$REPO" >/dev/null
    echo "closed #$n"
  done
fi
exit 0
