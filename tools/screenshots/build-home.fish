#!/usr/bin/env fish
# Build the fabricated home the README's screenshots are taken against.
#
# Every session, repository and account in here is invented. That is the whole
# point: the images are rendered pixels, so a real path in one cannot be found
# by grepping the history later - it has to not be there in the first place.
# capture.sh mounts this directory at /home/dev with bwrap, which is what makes
# "/home/dev/code/docs-site" a real path the collector can resolve rather than a
# string someone typed.
#
# Usage: build-home.fish [target-directory]

set -l here (dirname (realpath (status filename)))
# Global, not local: fish functions see globals, never the caller's locals.
set -g home $here/home
test (count $argv) -gt 0; and set -g home $argv[1]

rm -rf $home
mkdir -p $home/.claude/sessions $home/.claude-personal/sessions \
         $home/proc $home/.config $home/code $home/shots $home/frames \
         $home/.local/share/plasma/plasmoids

# The clock every age and uptime is measured against. The harness pins the
# widget's `now` to the same number, so "34m" is 34m in every capture whenever
# it runs - a screenshot that quietly re-times itself is a screenshot you cannot
# retake to match the others.
set -g NOW 1789000000000

for r in checkout-flow:main billing-api:release/2.4 docs-site:main \
         api-gateway:feature/rate-limits infra-scripts:main
    set -l parts (string split ':' $r)
    mkdir -p $home/code/$parts[1]/.git
    echo "ref: refs/heads/$parts[2]" >$home/code/$parts[1]/.git/HEAD
end

# A believable /proc/<pid>/stat: field 2 is the comm in parentheses, field 22
# the start time in clock ticks, which is what the collector checks a record
# against to rule out a recycled pid.
function fake_proc -a pid
    mkdir -p $home/proc/$pid/task/$pid
    set -l pad (string repeat -n 18 '0 ')
    # Assigned first: brace expansion does not happen inside double quotes, so
    # writing it inline puts a literal "{7001}00" in the file.
    set -l start $pid"00"
    echo "$pid (claude) S $pad $start" >$home/proc/$pid/stat
end

# `status` is a read-only fish builtin variable, hence `state`.
function record -a pid state name cwd extra
    test -n "$extra"; or set extra '{}'
    jq -n --argjson pid $pid --arg st $state --arg n $name --arg cwd $cwd \
          --argjson x $extra '
        {pid: $pid, sessionId: "11111111-2222-3333-4444-\($pid|tostring)00000000",
         cwd: $cwd, name: $n, kind: "interactive", status: $st,
         version: "2.1.263", startedAt: 0, updatedAt: 0, statusUpdatedAt: 0,
         procStart: "\($pid)00"} + $x' >$home/.claude/sessions/$pid.json
    fake_proc $pid
end

#      pid  state    name              directory                     uptime / status age
record 7001 waiting checkout-flow-7  /home/dev/code/checkout-flow \
    "{\"needs\":\"choose: allow or deny the Bash command\",\"startedAt\":"(math $NOW - 6300000)",\"statusUpdatedAt\":"(math $NOW - 2070000)"}"
record 7002 idle    billing-api-3    /home/dev/code/billing-api \
    "{\"startedAt\":"(math $NOW - 11040000)",\"statusUpdatedAt\":"(math $NOW - 2310000)"}"
record 7003 busy    docs-site-b2     /home/dev/code/docs-site \
    "{\"startedAt\":"(math $NOW - 4020000)",\"statusUpdatedAt\":"(math $NOW - 2130000)"}"
record 7004 busy    api-gateway-c1   /home/dev/code/api-gateway \
    "{\"startedAt\":"(math $NOW - 2760000)",\"statusUpdatedAt\":"(math $NOW - 2060000)"}"
record 7005 idle    infra-scripts-a9 /home/dev/code/infra-scripts \
    "{\"startedAt\":"(math $NOW - 18240000)",\"statusUpdatedAt\":"(math $NOW - 3090000)"}"

# Running: a busy session with a shell as a direct child. The collector reads
# the eval'd text out of the child's cmdline, so it has to be shaped like one.
mkdir -p $home/proc/70031
echo bash >$home/proc/70031/comm
printf '/bin/bash\0-c\0source /snap.sh || true && eval \'npm run build\' < /dev/null\0' \
    >$home/proc/70031/cmdline
echo -n "70031 " >$home/proc/7003/task/7003/children

# Error: an idle session whose transcript ends on a failed turn.
mkdir -p $home/.claude/projects/-home-dev-code-billing-api
jq -n -c '{type: "assistant", isApiErrorMessage: true,
           message: {role: "assistant", content: [{type: "text",
             text: "You have hit your session limit - resets 6:40pm"}]}}' \
    >$home/.claude/projects/-home-dev-code-billing-api/11111111-2222-3333-4444-700200000000.jsonl

# Both accounts need credentials to exist, and a .claude.json so the settings
# page's search finds them the way it would on a real machine.
for dir in $home/.claude $home/.claude-personal
    jq -n '{claudeAiOauth: {accessToken: "demo", expiresAt: 99999999999999}}' \
        >$dir/.credentials.json
    echo '{}' >$dir/.claude.json
end

cp ~/.config/kdeglobals $home/.config/
printf '\n[Icons]\nTheme=breeze-dark\n' >>$home/.config/kdeglobals
# Subpixel antialiasing paints coloured fringes down every glyph edge. Invisible
# on a screen, very visible in a PNG rendered at nine times the size.
sed -i 's/^XftSubPixel=.*/XftSubPixel=none/' $home/.config/kdeglobals
mkdir -p $home/.config/fontconfig
printf '<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font"><edit name="rgba" mode="assign"><const>none</const></edit></match>
</fontconfig>
' >$home/.config/fontconfig/fonts.conf

echo "home built at $home"
