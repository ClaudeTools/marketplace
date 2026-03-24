#!/bin/bash
# Scaffold a frontend project with design tokens and standard directories
# Usage: scaffold-project.sh [--framework next|vite|astro] [project-name]
# If no name given, initializes in current directory
# If no framework given, defaults to next

set -euo pipefail

FRAMEWORK="next"
PROJECT_NAME="."

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --framework)
      FRAMEWORK="$2"
      shift 2
      ;;
    *)
      PROJECT_NAME="$1"
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSETS_DIR="$(cd "$SCRIPT_DIR/../assets" && pwd)"

scaffold_next() {
  if [ "$PROJECT_NAME" != "." ]; then
    echo "Creating Next.js project: $PROJECT_NAME"
    npx create-next-app@latest "$PROJECT_NAME" --ts --tailwind --eslint --app --src-dir --import-alias "@/*" --use-pnpm --yes 2>/dev/null
    cd "$PROJECT_NAME"
  else
    if [ ! -f "package.json" ]; then
      echo "Not a project directory. Run with a project name to create one."
      exit 1
    fi
  fi

  # Install shadcn/ui if not already set up
  if [ ! -f "components.json" ]; then
    echo "Initializing shadcn/ui..."
    npx shadcn@latest init -d -y 2>/dev/null || echo "shadcn init skipped (may already exist)"
  fi

  # Install common dependencies
  echo "Installing dependencies..."
  pnpm add swr lucide-react 2>/dev/null || npm install swr lucide-react 2>/dev/null || true

  echo ""
  echo "  - Next.js with App Router + TypeScript"
  echo "  - shadcn/ui initialized"
  echo "  - SWR + Lucide React installed"
}

scaffold_vite() {
  if [ "$PROJECT_NAME" != "." ]; then
    echo "Creating Vite + React project: $PROJECT_NAME"
    npm create vite@latest "$PROJECT_NAME" -- --template react-ts 2>/dev/null
    cd "$PROJECT_NAME"
    npm install 2>/dev/null
  else
    if [ ! -f "package.json" ]; then
      echo "Not a project directory. Run with a project name to create one."
      exit 1
    fi
  fi

  # Install Tailwind CSS and dependencies
  echo "Installing Tailwind CSS..."
  npm install -D tailwindcss @tailwindcss/vite 2>/dev/null || true

  # Install common dependencies
  echo "Installing dependencies..."
  npm install lucide-react 2>/dev/null || true

  echo ""
  echo "  - Vite + React + TypeScript"
  echo "  - Tailwind CSS installed"
  echo "  - Lucide React installed"
}

scaffold_astro() {
  if [ "$PROJECT_NAME" != "." ]; then
    echo "Creating Astro project: $PROJECT_NAME"
    npm create astro@latest "$PROJECT_NAME" -- --template basics --install --no-git 2>/dev/null
    cd "$PROJECT_NAME"
  else
    if [ ! -f "package.json" ]; then
      echo "Not a project directory. Run with a project name to create one."
      exit 1
    fi
  fi

  # Add Tailwind integration
  echo "Adding Tailwind CSS..."
  npx astro add tailwind -y 2>/dev/null || true

  echo ""
  echo "  - Astro with Tailwind CSS"
}

# Run framework-specific scaffold
case "$FRAMEWORK" in
  next)    scaffold_next ;;
  vite)    scaffold_vite ;;
  astro)   scaffold_astro ;;
  *)
    echo "Unknown framework: $FRAMEWORK"
    echo "Supported: next, vite, astro"
    exit 1
    ;;
esac

# Common setup for all frameworks
mkdir -p components lib hooks public/images

# Copy design token template if globals.css doesn't have tokens yet
if [ -f "$ASSETS_DIR/globals-template.css" ]; then
  GLOBALS=$(find . -name "globals.css" -not -path "*/node_modules/*" 2>/dev/null | head -1)
  if [ -n "$GLOBALS" ]; then
    if ! grep -q '\-\-background' "$GLOBALS" 2>/dev/null; then
      echo "Design token template available at: $ASSETS_DIR/globals-template.css"
      echo "Copy it to your globals.css to get started with design tokens."
    fi
  fi
fi

# Create .frontend-design directory for system persistence
mkdir -p .frontend-design

echo ""
echo "Project scaffolded successfully!"
echo "  - Standard directories created: components/, lib/, hooks/"
echo ""
echo "Next steps:"
echo "  1. Run the design brief generator to establish your design system"
echo "  2. Customize globals.css with your design tokens"
echo "  3. Start building with your dev server"
