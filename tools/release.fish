#!/usr/bin/env fish
# Cut a release: bump the version, test, build the .plasmoid, tag it.
#
# One version string drives metadata.json, the git tag and the artifact name, so
# they cannot drift apart - which is the whole point.
#
# KPackage's update path only replaces files when the incoming version is
# strictly newer than the installed one, and KNewStuff reports success either
# way. So a store upload whose KPlugin.Version was not bumped installs nothing,
# tells every user it worked, and leaves them on the old build with no error
# anywhere. That is not a mistake you can catch by testing locally, because
# install.fish uses --upgrade, which replaces files regardless.
#
# Usage: release.fish <version>        e.g. release.fish 1.1.0

set -l repo (dirname (dirname (realpath (status filename))))
# Not `version`: that is fish's own, and `set -l version` is refused.
set -l newver $argv[1]

if test -z "$newver"
    echo "usage: release.fish <version>   e.g. 1.1.0"
    exit 2
end

# QVersionNumber::fromString stops at the first character that is not a digit or
# a dot, so "v1.2.3" parses as nothing and "1.2-beta" parses as 1.2. Either one
# silently fails the newer-than check forever.
if not string match -qr '^[0-9]+(\.[0-9]+)*$' -- $newver
    echo "✗ '$newver' is not a plain version number."
    echo "  Digits and dots only: KPackage parses it with QVersionNumber, which"
    echo "  stops at the first other character. No leading v, no -beta."
    exit 1
end

if test (count (git -C $repo status --porcelain)) -gt 0
    echo "✗ Working tree is not clean. Commit or stash first."
    git -C $repo status --short
    exit 1
end

if git -C $repo rev-parse -q --verify "refs/tags/v$newver" >/dev/null
    echo "✗ Tag v$newver already exists."
    exit 1
end

set -l metadata $repo/package/metadata.json
set -l current (jq -r '.KPlugin.Version' $metadata)
set -l id (jq -r '.KPlugin.Id' $metadata)

# Strictly newer, the same comparison KPackage makes.
function __newer -a a b # is $b newer than $a?
    set -l left (string split '.' -- $a)
    set -l right (string split '.' -- $b)
    for i in (seq (math (max (count $left) (count $right))))
        set -l l 0
        set -l r 0
        test (count $left) -ge $i; and set l $left[$i]
        test (count $right) -ge $i; and set r $right[$i]
        test $r -gt $l; and return 0
        test $r -lt $l; and return 1
    end
    return 1
end

if test "$current" != "$newver"; and not __newer $current $newver
    echo "✗ $newver is not newer than the current $current."
    echo "  KPackage would refuse to replace the installed files, and KNewStuff"
    echo "  would tell the user it worked anyway."
    exit 1
end

echo "→ $current → $newver"
jq --arg v $newver '.KPlugin.Version = $v' $metadata >$metadata.tmp
and mv $metadata.tmp $metadata
or begin
    echo "✗ Could not write $metadata"
    exit 1
end

echo "→ Tests"
fish --no-config $repo/test/test-collectors.fish | tail -1
or begin
    echo "✗ Collector tests failed."
    exit 1
end
node --test $repo/test/sessions.test.js $repo/test/usage.test.js >/dev/null
or begin
    echo "✗ JavaScript tests failed."
    exit 1
end
echo "  all green"

# The archive is the package directory's *contents*. KPackage copes with a
# single top-level wrapper directory but not with two top-level entries, so
# README and LICENSE stay out of it.
set -l artifact $repo/$id-$newver.plasmoid
rm -f $artifact
pushd $repo/package >/dev/null
zip -q -r $artifact . -x '*.git*'
popd >/dev/null
echo "→ $artifact ("(math (stat -c%s $artifact) / 1024)" KiB)"

git -C $repo add package/metadata.json
git -C $repo commit -q -m "Release v$newver"
git -C $repo tag -a "v$newver" -m "v$newver"
echo "→ Committed and tagged v$newver"

echo
echo "Next:"
echo "  git push && git push --tags"
echo "  Cut a GitHub release for v$newver and attach the .plasmoid"
echo
echo "  On the KDE Store, three version fields have to agree:"
echo "    1. KPlugin.Version in the archive   - already $newver"
echo "    2. the per-file Version column      - set it to $newver"
echo "    3. the product version field        - set it to $newver"
echo "  Keep exactly one non-archived file on the product, or users get a"
echo "  file picker instead of an update button."
