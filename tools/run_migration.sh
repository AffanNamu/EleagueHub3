#!/bin/bash
# Usage: bash tools/run_migration.sh
# Requires: node, firebase-admin npm package, service account JSON

cd "$(dirname "$0")/.."

if [ ! -f "tools/serviceAccount.json" ]; then
  echo "ERROR: Put your Firebase service account JSON at tools/serviceAccount.json"
  echo "Download from: Firebase Console → Project Settings → Service Accounts → Generate new private key"
  exit 1
fi

cd tools
if [ ! -d "node_modules" ]; then
  echo "Installing firebase-admin..."
  npm install firebase-admin
fi

cd ..
node tools/migrate_organizer_uid.js tools/serviceAccount.json
