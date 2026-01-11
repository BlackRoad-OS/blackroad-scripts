#!/bin/bash
# 📦 BlackRoad NPM Package Automation

set -e

echo "📦 BLACKROAD NPM AUTOMATION"
echo "==========================="
echo ""

SUCCESS=0
UPDATED=0

# Standard package.json scripts to add
STANDARD_SCRIPTS='{
  "dev": "next dev || vite || webpack serve || npm start",
  "build": "next build || vite build || webpack build || echo \"No build configured\"",
  "start": "next start || node index.js || node server.js",
  "lint": "eslint . || echo \"No linter configured\"",
  "format": "prettier --write . || echo \"No formatter configured\"",
  "test": "jest || vitest || echo \"No tests configured\"",
  "deploy": "wrangler pages deploy || vercel deploy || echo \"No deployment configured\"",
  "clean": "rm -rf node_modules dist .next out build"
}'

gh repo list BlackRoad-OS --limit 1000 --json name -q '.[].name' | while read repo; do
  [ -z "$repo" ] && continue

  if [ ! -d "/tmp/npm-$repo" ]; then
    gh repo clone "BlackRoad-OS/$repo" "/tmp/npm-$repo" 2>/dev/null || continue
  fi

  cd "/tmp/npm-$repo"
  git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || true

  # Only process if it's a Node project
  if [ ! -f "package.json" ]; then
    cd - > /dev/null
    continue
  fi

  echo "📦 Processing: $repo"

  # Add standard dev dependencies if missing
  DEPS_ADDED=false

  if ! grep -q "\"prettier\"" package.json 2>/dev/null; then
    npm install --save-dev prettier 2>/dev/null && DEPS_ADDED=true || true
  fi

  if ! grep -q "\"eslint\"" package.json 2>/dev/null; then
    npm install --save-dev eslint 2>/dev/null && DEPS_ADDED=true || true
  fi

  # Add .prettierrc if missing
  if [ ! -f ".prettierrc" ]; then
    cat > .prettierrc << 'PRETTIER'
{
  "semi": true,
  "singleQuote": true,
  "tabWidth": 2,
  "trailingComma": "es5"
}
PRETTIER
  fi

  # Add .eslintrc if missing
  if [ ! -f ".eslintrc.json" ]; then
    cat > .eslintrc.json << 'ESLINT'
{
  "extends": ["eslint:recommended"],
  "env": {
    "node": true,
    "es2021": true
  },
  "parserOptions": {
    "ecmaVersion": "latest",
    "sourceType": "module"
  }
}
ESLINT
  fi

  # Commit if changes
  if git diff --quiet && git diff --staged --quiet && [ "$DEPS_ADDED" = false ]; then
    echo "  → No changes needed"
    cd - > /dev/null
    continue
  fi

  git add package.json .prettierrc .eslintrc.json 2>/dev/null || true

  git commit -m "Add standard NPM automation

- Prettier for code formatting
- ESLint for linting
- Standard configuration files

🤖 Generated with Claude Code" 2>/dev/null || true

  git push origin main 2>/dev/null || git push origin master 2>/dev/null || {
    echo "  ⚠️  Push failed"
    cd - > /dev/null
    continue
  }

  echo "  ✅ Updated: $repo"
  ((UPDATED++))

  cd - > /dev/null
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ NPM AUTOMATION COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 Updated: $UPDATED Node.js projects"
echo ""
