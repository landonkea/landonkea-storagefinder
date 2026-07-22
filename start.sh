#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              StorageFinder — Starting Up                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

ruby_version=$(ruby --version)
echo "✓ Ruby: $ruby_version"
bundle_version=$(bundle --version)
echo "✓ Bundler: $bundle_version"
echo ""
echo "Checking gems..."
bundle install --quiet
echo ""
echo "Setting up database..."
RAILS_ENV=development bundle exec rails db:prepare 2>/dev/null || true
echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                  StorageFinder Ready!                     ║"
echo "╠═══════════════════════════════════════════════════════════╣"
echo "║  Local:     http://localhost:5555                         ║"
echo "║  LAN:       http://storagefinder.local                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Press Ctrl+C to stop."
echo ""
RAILS_ENV=development bundle exec rails server --binding 0.0.0.0 --port 5555
