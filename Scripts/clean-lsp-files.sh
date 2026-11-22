#!/bin/bash
# Deletes the build files sourcekit-lsp leaves in the package root: for each
# source file a Foo-2.d, Foo-2.swiftdeps, Foo-2.swiftmodule and Foo.dia (a
# diagnostics file). They are never wanted, and .gitignore already hides them.
#
#   Scripts/clean-lsp-files.sh        delete them
#   Scripts/clean-lsp-files.sh -n     only list them
#
# Only regular files directly in the package root, by those four extensions.
# Nothing in a subfolder is touched, and neither is anything git tracks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

dry_run=0
[ "${1:-}" = "-n" ] && dry_run=1

count=0
while IFS= read -r -d '' file; do
    name="${file#./}"
    if git ls-files --error-unmatch -- "$name" >/dev/null 2>&1; then
        echo "kept (tracked): $name" >&2
        continue
    fi
    count=$((count + 1))
    if [ "$dry_run" -eq 1 ]; then
        echo "$name"
    else
        rm -f -- "$name"
    fi
done < <(find . -maxdepth 1 -type f \
    \( -name '*.d' -o -name '*.dia' -o -name '*.swiftdeps' -o -name '*.swiftmodule' \) -print0)

if [ "$dry_run" -eq 1 ]; then
    echo "$count files would be deleted"
else
    echo "deleted $count files"
fi
