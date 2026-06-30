#!/usr/bin/env bash
# Generates QuaraMoney/Supabase/SupabaseSecrets.swift from the gitignored
# supabase/secrets.local.xcconfig. Run after cloning or whenever the key changes.
#
#   ./supabase/gen-secrets.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/supabase/secrets.local.xcconfig"
OUT="$ROOT/QuaraMoney/Supabase/SupabaseSecrets.swift"

if [ ! -f "$CFG" ]; then
  echo "error: missing $CFG"
  echo "       copy supabase/secrets.example.xcconfig to secrets.local.xcconfig and fill it in."
  exit 1
fi

url=$(grep -E '^[[:space:]]*SUPABASE_URL'      "$CFG" | sed 's/^[^=]*=//' | xargs)
key=$(grep -E '^[[:space:]]*SUPABASE_ANON_KEY' "$CFG" | sed 's/^[^=]*=//' | xargs)

if [ -z "$url" ] || [ -z "$key" ] || [[ "$key" == *PASTE* ]]; then
  echo "error: SUPABASE_URL / SUPABASE_ANON_KEY not set in $CFG"
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<EOF
// AUTO-GENERATED from supabase/secrets.local.xcconfig — do not edit by hand.
// Gitignored: holds the anon/publishable key. Regenerate: ./supabase/gen-secrets.sh
import Foundation

enum SupabaseSecrets {
    static let url = "$url"
    static let anonKey = "$key"
}
EOF
echo "Wrote $OUT"
