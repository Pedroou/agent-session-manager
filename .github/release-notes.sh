#!/bin/sh
# Prints CHANGELOG.md's section for one version (1.2.0 or v1.2.0): its release notes.
awk -v head="## [${1#v}]" '
    index($0, "## ") == 1 { p = index($0, head) == 1; next }
    /^\[[^]]*\]: / { next }
    p' "$(dirname "$0")/../CHANGELOG.md"
