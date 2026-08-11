#!/usr/bin/env bash
# check-tokens — fails if UI chrome invents its own colours (NOD-131).
#
# The old build ended with 95 raw Color3 calls spread across nine controllers
# and THREE different rarity palettes that disagreed with each other. Nothing
# was wrong with any individual line; the problem was that repainting the game
# meant finding all 95, and missing one was invisible until someone opened that
# panel.
#
# Run from the repo root:   bash scripts/check-tokens.sh
#
# Exempt on purpose:
#   client/UI/Theme.luau      — the token definitions themselves
#   shared/Config/Rarity.luau — rarity is game data, and owns its own palette
#   shared/Config/*Catalog    — gun skin colours are CONTENT, not chrome. A
#                               bubblegum slide is an art asset expressed as a
#                               Color3, not a UI decision.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

violations=$(grep -rn "Color3\.fromRGB\|Color3\.fromHSV" src/client --include=*.luau \
  | grep -v "src/client/UI/Theme.luau" \
  || true)

# Color3.new is allowed only for pure white/black, which are not brand colours
# and reading them from a token would be noise.
suspicious_new=$(grep -rn "Color3\.new(" src/client --include=*.luau \
  | grep -v "src/client/UI/Theme.luau" \
  | grep -vE "Color3\.new\(([01]),\s*([01]),\s*([01])\)" \
  || true)

fail=0

if [ -n "$violations" ]; then
  echo "❌ raw Color3 in client UI — use a token from UI/Theme.luau instead:"
  echo "$violations" | sed 's/^/   /'
  fail=1
fi

if [ -n "$suspicious_new" ]; then
  echo "❌ Color3.new with non-trivial values — add a token instead:"
  echo "$suspicious_new" | sed 's/^/   /'
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  count=$(grep -rc "Color3\." src/client/UI/Theme.luau | head -1)
  echo "✅ no raw colours in client UI — every chrome colour comes from Theme"
  exit 0
fi

echo
echo "If a value is genuinely content rather than chrome (a gun skin, a camo),"
echo "it belongs in shared/Config, not in a controller."
exit 1
