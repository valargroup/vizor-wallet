#!/bin/bash
# Clear the Zcash wallet app data on macOS (including keychain data)

BUNDLE_ID="com.zcash.zcashWallet"
CONTAINER="$HOME/Library/Containers/$BUNDLE_ID"

# Kill the app if running
pkill -f "$BUNDLE_ID" 2>/dev/null

# Remove app container (DB, preferences, caches)
if [ -d "$CONTAINER" ]; then
  rm -rf "$CONTAINER"
  echo "Removed app container: $CONTAINER"
else
  echo "No app container found"
fi

# Remove keychain items (flutter_secure_storage)
security delete-generic-password -s "flutter_secure_storage_service" 2>/dev/null && \
  echo "Removed keychain items" || \
  echo "No keychain items found"

echo "macOS app cleared (container + keychain)"
