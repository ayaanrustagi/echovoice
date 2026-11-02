#!/bin/bash
# Exercises app-language selection with real compiled catalogs, without a simulator.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/LocalizationSmoke.app/Contents"
mkdir -p "$APP/MacOS" "$APP/Resources"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.echovoice.localization-smoke</string>
<key>CFBundleExecutable</key><string>LocalizationSmoke</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
</dict></plist>
PLIST
xcrun xcstringstool compile --output-directory "$APP/Resources" "$ROOT/EchoVoice/Localizable.xcstrings"
xcrun swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" -module-cache-path "$WORK/ModuleCache" \
  "$ROOT/Tests/SpanishLocalizationSmoke.swift" \
  "$ROOT/EchoVoice/Model/AppLanguage.swift" \
  "$ROOT/EchoVoice/Model/AACVocabulary.swift" \
  "$ROOT/EchoVoice/Model/PartnerReplySuggester.swift" \
  -o "$APP/MacOS/LocalizationSmoke"
"$APP/MacOS/LocalizationSmoke" -AppleLanguages '(en)' -AppleLocale en_US
"$APP/MacOS/LocalizationSmoke" -AppleLanguages '(es-MX)' -AppleLocale es_MX --spanish
