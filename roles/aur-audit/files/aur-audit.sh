#!/usr/bin/env bash
# aur-audit.sh — AUR supply-chain audit for an Arch workstation.
#
# Origin: BezaForge #618 (2026-08-02), after the June 2026 AUR incident in which
# attackers ADOPTED orphaned AUR packages and added build-time hooks that pulled
# a Rust infostealer + optional eBPF rootkit.
#
# The lesson that shaped this script: the tell was NOT a suspicious-looking diff.
# It was a MAINTAINER CHANGE. A package you have trusted for years silently
# changes hands, and the next routine upgrade builds someone else's code. So the
# primary check here is maintainer churn, not pattern matching.
#
# Everything this does is READ-ONLY. It never installs, removes, or modifies a
# package. It reads the paru clone cache's git history, which is a faithful
# record of what was actually fetched and built on this machine.
#
# Exit codes:  0 = no findings   1 = findings need review   2 = script error
#
# Usage:
#   aur-audit.sh [--days N] [--quiet] [--self-test]
#
#   --days N     look back N days (default 30)
#   --quiet      only emit output when there are findings (for timer/cron use)
#   --self-test  prove the detectors can go red, then exit

set -uo pipefail

CLONE_DIR="${PARU_CLONE_DIR:-$HOME/.cache/paru/clone}"
DAYS=30
QUIET=0
SELFTEST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)      DAYS="${2:?--days needs a value}"; shift 2 ;;
    --quiet)     QUIET=1; shift ;;
    --self-test) SELFTEST=1; shift ;;
    -h|--help)   sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Known-malicious npm packages from the June 2026 campaign. Extend as new
# campaigns are disclosed -- this list is a floor, never a ceiling.
IOC_STRINGS='atomic-lockfile|js-digest'

# Generic build-time-execution patterns. These are NOT inherently malicious --
# plenty of legitimate PKGBUILDs invoke npm -- so they are reported as
# "inspect", never as "compromised".
SUSPECT_PATTERNS='npm (install|i) |curl [^|]*\| *(ba)?sh|wget [^|]*\| *(ba)?sh|base64 -d|eval .*\$\('

FINDINGS=0
REPORT=""

emit() { REPORT+="$1"$'\n'; }

# ---------------------------------------------------------------------------
# Self-test: build a throwaway git repo that SHOULD trip each detector.
# A detector that has never been observed going red is not a detector.
# ---------------------------------------------------------------------------
if [[ $SELFTEST -eq 1 ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/evil-pkg"
  cd "$tmp/evil-pkg" || exit 2
  git init -q .
  printf 'pkgname=evil-pkg\nprepare() { npm install atomic-lockfile; }\n' > PKGBUILD
  git add PKGBUILD
  GIT_AUTHOR_NAME="Original Maintainer" GIT_AUTHOR_EMAIL="orig@example.com" \
    git -c user.name="Original Maintainer" -c user.email="orig@example.com" \
    commit -q -m "initial"
  printf 'pkgname=evil-pkg\nprepare() { npm install atomic-lockfile; }\n# takeover\n' > PKGBUILD
  git add PKGBUILD
  GIT_AUTHOR_NAME="Takeover Actor" GIT_AUTHOR_EMAIL="evil@example.com" \
    git -c user.name="Takeover Actor" -c user.email="evil@example.com" \
    commit -q -m "adopt package"

  ioc_hit=0; churn_hit=0
  git grep -InE "$IOC_STRINGS" "$(git rev-list --all | head -1)" -- >/dev/null 2>&1 && ioc_hit=1
  n_auth=$(git log --pretty=format:'%ae' | sort -u | wc -l)
  [[ "$n_auth" -gt 1 ]] && churn_hit=1

  echo "SELF-TEST"
  echo "  IOC detector went red:              $([[ $ioc_hit -eq 1 ]] && echo YES || echo 'NO  <-- BROKEN')"
  echo "  maintainer-churn detector went red: $([[ $churn_hit -eq 1 ]] && echo YES || echo 'NO  <-- BROKEN')"
  if [[ $ioc_hit -eq 1 && $churn_hit -eq 1 ]]; then
    echo "  => both detectors can fail. Script is trustworthy."; exit 0
  fi
  echo "  => A DETECTOR CANNOT GO RED. Do not trust a clean run."; exit 2
fi

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
if [[ ! -d "$CLONE_DIR" ]]; then
  echo "aur-audit: clone cache not found at $CLONE_DIR" >&2
  echo "aur-audit: (paru may not be installed, or PARU_CLONE_DIR is wrong)" >&2
  exit 2
fi

SINCE="$(date -d "-${DAYS} days" +%Y-%m-%d)"
mapfile -t PKGS < <(pacman -Qmq 2>/dev/null | sort)
SCANNED=0
NO_CLONE=()

emit "AUR supply-chain audit — $(date '+%Y-%m-%d %H:%M:%S %Z')"
emit "Window: since ${SINCE} (${DAYS} days) · installed AUR packages: ${#PKGS[@]}"
emit ""

# ---------------------------------------------------------------------------
# 1. Maintainer churn — the primary signal
# ---------------------------------------------------------------------------
CHURN=""
for p in "${PKGS[@]}"; do
  d="$CLONE_DIR/$p"
  if [[ ! -d "$d/.git" ]]; then NO_CLONE+=("$p"); continue; fi
  SCANNED=$((SCANNED+1))
  mapfile -t authors < <(git -C "$d" log --since="$SINCE" --pretty=format:'%an <%ae>' 2>/dev/null | sort -u)
  if [[ ${#authors[@]} -gt 1 ]]; then
    CHURN+="  ! ${p} — ${#authors[@]} distinct committers in window:"$'\n'
    for a in "${authors[@]}"; do CHURN+="      ${a}"$'\n'; done
    CHURN+="      inspect: git -C ${d} log --since=${SINCE} -p"$'\n'
  fi
done

if [[ -n "$CHURN" ]]; then
  emit "[1] MAINTAINER CHURN — packages that changed hands in the window"
  emit "    (this is the exact pattern the June 2026 campaign used; a shared"
  emit "     identity across two git names is common and usually benign)"
  emit "$CHURN"
  FINDINGS=1
else
  emit "[1] MAINTAINER CHURN ............ none"
fi

# ---------------------------------------------------------------------------
# 2. Known IOC strings across FULL git history (not just checked-out files)
# ---------------------------------------------------------------------------
IOC=""
for p in "${PKGS[@]}"; do
  d="$CLONE_DIR/$p"
  [[ -d "$d/.git" ]] || continue
  revs="$(git -C "$d" rev-list --all 2>/dev/null)"
  [[ -z "$revs" ]] && continue
  # shellcheck disable=SC2086
  hit="$(git -C "$d" grep -InE "$IOC_STRINGS" $revs -- 2>/dev/null | head -3)"
  [[ -n "$hit" ]] && IOC+="  !! ${p}"$'\n'"${hit}"$'\n'
done

if [[ -n "$IOC" ]]; then
  emit "[2] KNOWN-MALICIOUS IOC STRINGS ....... FOUND — treat as compromise"
  emit "$IOC"
  FINDINGS=1
else
  emit "[2] KNOWN IOC STRINGS .......... none"
fi

# ---------------------------------------------------------------------------
# 3. Build-time execution patterns in current PKGBUILDs (informational)
# ---------------------------------------------------------------------------
SUS=""
while IFS= read -r line; do
  [[ -n "$line" ]] && SUS+="  ~ ${line}"$'\n'
done < <(grep -rInE --include='PKGBUILD' --include='*.install' "$SUSPECT_PATTERNS" "$CLONE_DIR" 2>/dev/null \
          | sed "s|$CLONE_DIR/||" | head -25)

if [[ -n "$SUS" ]]; then
  emit "[3] BUILD-TIME EXECUTION (inspect, not an alert)"
  emit "    Legitimate for source-built packages. Confirm each is expected."
  emit "$SUS"
else
  emit "[3] BUILD-TIME EXECUTION ....... none"
fi

# ---------------------------------------------------------------------------
# 4. Orphaned AUR packages — pure attack surface, safe to consider removing
# ---------------------------------------------------------------------------
mapfile -t ORPHANS < <(pacman -Qmdtq 2>/dev/null)
if [[ ${#ORPHANS[@]} -gt 0 ]]; then
  emit "[4] ORPHANED AUR PACKAGES (${#ORPHANS[@]}) — required by nothing"
  emit "    Each is attack surface with no consumer. Review then:"
  emit "      sudo pacman -Rns ${ORPHANS[*]}"
  for o in "${ORPHANS[@]}"; do emit "      - $o"; done
else
  emit "[4] ORPHANED AUR PACKAGES ...... none"
fi

# ---------------------------------------------------------------------------
# Coverage — never let a partial scan read as a clean one
# ---------------------------------------------------------------------------
emit ""
emit "Coverage: ${SCANNED}/${#PKGS[@]} installed AUR packages had a local clone and were scanned."
if [[ ${#NO_CLONE[@]} -gt 0 ]]; then
  emit "NOT SCANNED (no clone in cache — history unavailable, NOT proven clean):"
  for n in "${NO_CLONE[@]}"; do emit "  - $n"; done
  emit "  (paru prunes clones; re-fetch with: paru -G <pkg>)"
fi

if [[ $FINDINGS -eq 0 ]]; then
  emit ""
  emit "RESULT: no findings. Note this bounds only what was measured above —"
  emit "an eBPF rootkit hides its own artifacts and is out of scope here."
fi

if [[ $QUIET -eq 1 && $FINDINGS -eq 0 ]]; then
  exit 0
fi

printf '%s' "$REPORT"
exit "$FINDINGS"
