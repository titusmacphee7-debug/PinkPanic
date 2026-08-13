#!/usr/bin/env bash
# validate_assets.sh — the acceptance check from docs/COWORK_BRIEF.md §7.
#
# Reads the delivered .obj files and reports, per asset, exactly what is wrong.
# Trusts nothing in MANIFEST.md: the manifest is the supplier's claim and this
# is the check. They have disagreed before.
#
#   ./tools/validate_assets.sh assets/stage1
#
# Exit 0 if every asset passes, 1 otherwise.

set -uo pipefail
ROOT="${1:-assets/stage1}"

pass=0; fail=0
declare -a problems

ceiling_for() {
  case "$1" in
    Pistol|MachinePistol|Revolver|Melee) echo 2500 ;;
    SMG|Shotgun)                         echo 3500 ;;
    Rifle|BattleRifle)                   echo 4500 ;;
    Marksman|Sniper|Launcher)            echo 5000 ;;
    LMG)                                 echo 6000 ;;
    *)                                   echo 0    ;;
  esac
}

# Moving parts each class must actually have, from the brief's per-class notes.
#
# `Mag` is required on every magazine-fed class, because it is the part that
# DROPS on reload — a mag-fed weapon without one has nothing to animate, and the
# reload silently becomes a pause. The first version of this script only checked
# it on sidearms and let an AK-47 with no magazine through.
required_moving() {
  case "$1" in
    Pistol)                     echo "Slide Mag" ;;
    MachinePistol)              echo "Mag" ;;   # Slide or Bolt, checked separately
    Revolver)                   echo "Cylinder" ;;
    Rifle|SMG|BattleRifle|LMG)  echo "Bolt Mag" ;;
    Marksman)                   echo "Mag" ;;
    *)                          echo "" ;;
  esac
}

# Archetypes with a genuinely INTERNAL magazine, where no `Mag` object is the
# honest answer rather than an omission. Both are stripper-clip rifles; their
# reload animates the bolt, not a magazine drop.
internal_magazine() {
  case "$1" in
    Sniper_M700|Sniper_Mosin) return 0 ;;
    *)                        return 1 ;;
  esac
}

RESERVED="Body Panel Grip Hardware Accent Slide Bolt Pump Cylinder Mag Muzzle EjectPort LeftGrip Sight MagWell"

check_weapon() {
  local f="$1" id class objs tris why
  id="$(basename "$f" .obj)"
  class="${id%%_*}"
  objs="$(awk '/^o /{printf "%s ", $2}' "$f")"
  tris="$(grep -c '^f ' "$f")"
  why=""

  # Skin regions: at least one of Body/Panel AND one of Grip/Hardware/Accent.
  echo "$objs" | grep -qE '\b(Body|Panel)\b'          || why="$why; no Body or Panel"
  echo "$objs" | grep -qE '\b(Grip|Hardware|Accent)\b' || why="$why; no Grip/Hardware/Accent"

  # All five is the aim, not the bar — reported separately as a note.
  local missing5=""
  for r in Body Panel Grip Hardware Accent; do
    echo "$objs" | grep -qE "\b$r\b" || missing5="$missing5 $r"
  done

  for part in $(required_moving "$class"); do
    if [ "$part" = "Mag" ] && internal_magazine "$id"; then continue; fi
    echo "$objs" | grep -qE "\b$part\b" || why="$why; missing $part"
  done
  # Snipers are bolt guns; the Bolt is the reload.
  if [ "$class" = "Sniper" ]; then
    echo "$objs" | grep -qE '\bBolt\b' || why="$why; missing Bolt"
    internal_magazine "$id" || echo "$objs" | grep -qE '\bMag\b' || why="$why; missing Mag"
  fi
  if [ "$class" = "MachinePistol" ]; then
    echo "$objs" | grep -qE '\b(Slide|Bolt)\b' || why="$why; missing Slide or Bolt"
  fi

  local ceil; ceil="$(ceiling_for "$class")"
  if [ "$ceil" -gt 0 ] && [ "$tris" -gt "$ceil" ]; then
    why="$why; $tris tris over the $ceil ceiling"
  fi

  # Non-triangular faces would import as something other than what was counted.
  local nontri; nontri="$(awk '/^f /{if (NF-1 != 3) n++} END{print n+0}' "$f")"
  [ "$nontri" -eq 0 ] || why="$why; $nontri non-triangle faces"

  # Muzzle down -Z: the far end of the weapon must be negative.
  local minz; minz="$(awk '/^v /{if (m==""||$4<m) m=$4} END{printf "%.2f", m}' "$f")"
  awk -v z="$minz" 'BEGIN{exit !(z < -0.3)}' || why="$why; muzzle not down -Z (min Z $minz)"

  # Origin at the grip: (0,0,0) must fall inside the Grip object's Z span.
  if echo "$objs" | grep -qE '\bGrip\b'; then
    local ok; ok="$(awk '
      /^o /{o=$2; next}
      /^v /{ if (o=="Grip") { if (c==0){lo=$4;hi=$4} if($4<lo)lo=$4; if($4>hi)hi=$4; c++ } }
      END{ print (lo<=0 && hi>=0) ? "yes" : "no" }' "$f")"
    [ "$ok" = "yes" ] || why="$why; origin not inside the Grip"
  fi

  if [ -n "$why" ]; then
    problems+=("FAIL $id (${class}) ${why#; }")
    fail=$((fail+1))
  else
    pass=$((pass+1))
    [ -n "$missing5" ] && problems+=("note $id has no$missing5 — colours fine, fewer skin regions")
  fi
}

check_attachment() {
  local f="$1" id objs tris why
  id="$(basename "$f" .obj)"
  objs="$(awk '/^o /{printf "%s ", $2}' "$f")"
  tris="$(grep -c '^f ' "$f")"
  why=""

  echo "$objs" | grep -qE "\b${id}_Body\b" || why="$why; no ${id}_Body"

  # Reserved names would be read as the WEAPON's regions once equipped.
  # `Lens` is the single permitted exception, and only on optics.
  for name in $RESERVED; do
    if echo "$objs" | grep -qE "(^| )$name( |$)"; then
      why="$why; uses reserved name '$name'"
    fi
  done

  [ "$tris" -le 1200 ] || why="$why; $tris tris over the 1200 ceiling"

  local nontri; nontri="$(awk '/^f /{if (NF-1 != 3) n++} END{print n+0}' "$f")"
  [ "$nontri" -eq 0 ] || why="$why; $nontri non-triangle faces"

  if [ -n "$why" ]; then
    problems+=("FAIL $id ${why#; }")
    fail=$((fail+1))
  else
    pass=$((pass+1))
  fi
}

echo "== weapons =="
for f in "$ROOT"/*.obj; do [ -e "$f" ] && check_weapon "$f"; done
echo "== attachments =="
for f in "$ROOT"/attachments/*.obj; do [ -e "$f" ] && check_attachment "$f"; done

for p in "${problems[@]}"; do echo "  $p"; done
echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
