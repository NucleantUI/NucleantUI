#!/bin/bash
# Builds the documentation site for GitHub Pages: the DocC catalog in
# Sources/NucleantUI/NucleantUI.docc with NucleantUI's symbols, the
# Kivy → NucleantUI playground next to it, and the examples, each a page
# running the app.
#
#   Scripts/build-docs.sh [output-dir]
#
# Output defaults to .build/docs-site, laid out to be served at
# https://nucleantui.github.io/NucleantUI/ — the site's root is the
# repository's Pages path. To look at it locally:
#
#   mkdir -p /tmp/pages && ln -sfn "$PWD/.build/docs-site" /tmp/pages/NucleantUI
#   python3 -m http.server -d /tmp/pages 8000
#   open http://localhost:8000/NucleantUI/
#
# HOSTING_BASE_PATH (default NucleantUI) is that path. The playground link in
# Articles/KivyToNucleantUI.md is written against it, so change both together.
# SKIP_PLAYGROUND=1 leaves the playground out (it needs a wasm Swift SDK; see
# Scripts/build-playground.sh). SKIP_EXAMPLES=1 leaves the examples out (the
# same SDK; see Scripts/build_examples_wasm.py); the links to them in
# Examples/*Example.md are written against /$BASE_PATH/examples/ too.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$(mkdir -p "${1:-$ROOT/.build/docs-site}" && cd "${1:-$ROOT/.build/docs-site}" && pwd)"
BASE_PATH="${HOSTING_BASE_PATH:-NucleantUI}"
CATALOG="$ROOT/Sources/NucleantUI/NucleantUI.docc"
GRAPHS="$ROOT/.build/symbol-graphs"
MODULE_GRAPHS="$ROOT/.build/symbol-graphs-NucleantUI"

# 1. NucleantUI's symbol graph. The flags reach every module the build
#    compiles, so only NucleantUI's own graphs are kept for DocC.
echo "Extracting NucleantUI's symbols…"
rm -rf "$GRAPHS" "$MODULE_GRAPHS"
mkdir -p "$GRAPHS" "$MODULE_GRAPHS"
cd "$ROOT"
swift build --target NucleantUI \
    -Xswiftc -emit-symbol-graph \
    -Xswiftc -emit-symbol-graph-dir -Xswiftc "$GRAPHS" \
    -Xswiftc -symbol-graph-minimum-access-level -Xswiftc public
cp "$GRAPHS"/NucleantUI.symbols.json "$MODULE_GRAPHS"/
cp "$GRAPHS"/NucleantUI@*.symbols.json "$MODULE_GRAPHS"/ 2>/dev/null || true

# 2. The catalog, converted for static hosting under /$BASE_PATH/.
echo "Converting the catalog…"
rm -rf "$OUTPUT"
xcrun docc convert "$CATALOG" \
    --fallback-display-name NucleantUI \
    --fallback-bundle-identifier org.nucleantui.NucleantUI \
    --additional-symbol-graph-dir "$MODULE_GRAPHS" \
    --transform-for-static-hosting \
    --hosting-base-path "$BASE_PATH" \
    --output-path "$OUTPUT"

# The site's root opens the documentation rather than DocC's empty route.
cat > "$OUTPUT/index.html" <<EOF
<!DOCTYPE html>
<meta charset="utf-8">
<title>NucleantUI</title>
<meta http-equiv="refresh" content="0; url=/$BASE_PATH/documentation/nucleantui/">
<link rel="canonical" href="/$BASE_PATH/documentation/nucleantui/">
<a href="/$BASE_PATH/documentation/nucleantui/">NucleantUI documentation</a>
EOF
touch "$OUTPUT/.nojekyll"

# 3. The playground, served at /$BASE_PATH/kivy-to-nucleantui/.
if [ "${SKIP_PLAYGROUND:-0}" != "1" ]; then
    "$ROOT/Scripts/build-playground.sh" "$OUTPUT/kivy-to-nucleantui"
fi

# 4. The examples, served at /$BASE_PATH/examples/<Example>/.
if [ "${SKIP_EXAMPLES:-0}" != "1" ]; then
    python3 "$ROOT/Scripts/build_examples_wasm.py" "$OUTPUT/examples"
fi

echo "Documentation site: $OUTPUT"
