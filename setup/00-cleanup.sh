#!/bin/sh
set -e

echo "🧹 Cleaning up existing kind cluster..."
kind delete cluster --name kind 2>/dev/null || true

echo "🧹 Removing temporary files..."
rm -f .env
rm -f gcp-creds.json
rm -f aws-creds.conf
rm -f azure-creds.json

echo "✅ Cleanup complete! You can now run ./setup/00-intro.sh"

