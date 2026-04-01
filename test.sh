#!/bin/bash
set -e

echo "🧪 ShopSavvy Huginn Agent Tests"
echo "================================"

if [ "$1" = "--integration" ]; then
  if [ -z "$SHOPSAVVY_API_KEY" ]; then
    echo "❌ Set SHOPSAVVY_API_KEY env var to run integration tests"
    echo "   Get a key at https://shopsavvy.com/data"
    exit 1
  fi
  echo "Running integration tests (live API)..."
  echo ""
  echo "Testing API connectivity..."
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $SHOPSAVVY_API_KEY" \
    -H "User-Agent: ShopSavvy-Huginn-Test/1.0" \
    "https://api.shopsavvy.com/v1/usage")
  if [ "$RESPONSE" = "200" ]; then
    echo "  ✅ API key valid"
  else
    echo "  ❌ API returned HTTP $RESPONSE"
    exit 1
  fi

  echo "Testing product search..."
  SEARCH=$(curl -s \
    -H "Authorization: Bearer $SHOPSAVVY_API_KEY" \
    -H "User-Agent: ShopSavvy-Huginn-Test/1.0" \
    "https://api.shopsavvy.com/v1/products/search?q=airpods+pro&limit=1")
  if echo "$SEARCH" | grep -q '"success":true'; then
    echo "  ✅ Product search works"
  else
    echo "  ❌ Product search failed"
    exit 1
  fi

  echo ""
  echo "✅ All integration tests passed"
else
  echo "Running structural checks..."
  echo ""
  echo "Note: RSpec tests require a Huginn Rails environment."
  echo "Full specs run inside Huginn via: ADDITIONAL_GEMS=huginn_shopsavvy_agent bundle exec rspec"
  echo ""

  echo "Checking required files..."
  REQUIRED="lib/huginn_shopsavvy_agent.rb lib/huginn_shopsavvy_agent/shopsavvy_api_client.rb lib/huginn_shopsavvy_agent/shopsavvy_product_lookup_agent.rb lib/huginn_shopsavvy_agent/shopsavvy_price_monitor_agent.rb lib/huginn_shopsavvy_agent/shopsavvy_deal_discovery_agent.rb huginn_shopsavvy_agent.gemspec"
  MISSING=0
  for f in $REQUIRED; do
    if [ ! -f "$f" ]; then
      echo "  ❌ Missing: $f"
      MISSING=$((MISSING + 1))
    fi
  done
  if [ $MISSING -eq 0 ]; then
    echo "  ✅ All required files present ($(echo $REQUIRED | wc -w | tr -d ' ') files)"
  else
    echo "  ❌ $MISSING required files missing"
    exit 1
  fi

  echo "Checking Ruby syntax..."
  if command -v ruby &> /dev/null; then
    ERRORS=0
    for f in $(find lib -name "*.rb"); do
      if ! ruby -c "$f" > /dev/null 2>&1; then
        echo "  ❌ Syntax error: $f"
        ERRORS=$((ERRORS + 1))
      fi
    done
    if [ $ERRORS -eq 0 ]; then
      echo "  ✅ All Ruby files pass syntax check"
    else
      echo "  ❌ $ERRORS files have syntax errors"
      exit 1
    fi
  else
    echo "  ⚠️  Ruby not installed — skipping syntax check"
  fi

  echo "Checking gemspec..."
  if command -v ruby &> /dev/null; then
    ruby -e "eval(File.read('huginn_shopsavvy_agent.gemspec'))" 2>/dev/null && echo "  ✅ Gemspec is valid" || echo "  ⚠️  Gemspec needs Huginn context to fully validate"
  fi

  echo ""
  echo "✅ All unit checks passed"
fi
