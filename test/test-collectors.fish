#!/usr/bin/env fish
# Sandbox tests for the panel widget's collectors (plasmoid .../scripts/agent-sessions and agent-usage).
# MUST run with: fish --no-config
set -g REPO (dirname (dirname (realpath (status filename))))
set -g COLLECT $REPO/package/contents/scripts/agent-sessions
set -g USAGE $REPO/package/contents/scripts/agent-usage
set -g ROOT (mktemp -d)/sandbox
set -g PASS 0
set -g FAIL 0

# Tripwire: this suite must never write into the real session registry. Its
# mtimes move on their own - every live Claude Code session rewrites its record
# every few seconds - so the check is that none of the pids this suite invents
# ever turn up there. Captured before `setup` overrides $HOME; never hardcode a
# home path, or the check has nothing to look at.
function __registry_records -a home
    find $home/.claude/sessions $home/.claude-personal/sessions \
        -name '*.json' -printf '%f\n' 2>/dev/null | sort | string join ' '
end
set -g REAL_HOME $HOME
set -g REAL_BEFORE (__registry_records $REAL_HOME)

function check -a name expected actual
    if test "$expected" = "$actual"
        set PASS (math $PASS + 1); echo "  ✓ $name"
    else
        set FAIL (math $FAIL + 1); echo "  ✗ $name"
        echo "      expected: [$expected]"
        echo "      actual:   [$actual]"
    end
end

function setup
    rm -rf $ROOT
    set -g HOME $ROOT
    set -gx AGENT_SESSIONS_PROC $ROOT/proc
    set -e AGENT_SESSIONS_NO_ERROR
    mkdir -p $ROOT/.claude/sessions $ROOT/.claude-personal/sessions $ROOT/proc
    # The two accounts most of this suite was written against, configured the
    # way the widget configures them. Task 27 unsets this to check what happens
    # when nothing is.
    set -gx CLAUDE_PROFILES '[{"name":"work","dir":"'$ROOT'/.claude"},
                              {"name":"personal","dir":"'$ROOT'/.claude-personal"}]'
end

# A believable /proc/<pid>/stat: field 2 is the comm in parentheses, field 22 the
# start time in clock ticks. Fields 3..21 are placeholders.
function fake_proc -a pid starttime comm
    test -n "$comm"; or set comm claude
    mkdir -p $AGENT_SESSIONS_PROC/$pid
    set -l pad
    for i in (seq 18)
        set -a pad 0
    end
    echo "$pid ($comm) S "(string join ' ' $pad)" $starttime" >$AGENT_SESSIONS_PROC/$pid/stat
end

# Give `pid` a child process, the way Claude Code's Bash tool does.
function fake_child -a pid kid comm command
    mkdir -p $AGENT_SESSIONS_PROC/$pid/task/$pid $AGENT_SESSIONS_PROC/$kid
    echo -n "$kid " >>$AGENT_SESSIONS_PROC/$pid/task/$pid/children
    echo $comm >$AGENT_SESSIONS_PROC/$kid/comm
    string join0 -- /bin/bash -c "source /snap.sh || true && eval '$command' < /dev/null && pwd -P" \
        >$AGENT_SESSIONS_PROC/$kid/cmdline
end

# Write a transcript for a session, one JSON entry per line.
function fake_transcript -a session_id
    set -l dir $ROOT/.claude/projects/-some-project
    mkdir -p $dir
    printf '%s\n' $argv[2..] >$dir/$session_id.jsonl
end

function api_error -a text
    jq -n -c --arg t $text '{type: "assistant", isApiErrorMessage: true,
                             message: {role: "assistant", content: [{type: "text", text: $t}]}}'
end

function normal_reply -a text
    jq -n -c --arg t $text '{type: "assistant", message: {role: "assistant",
                             content: [{type: "text", text: $t}]}}'
end

# Write a session record. Extra JSON fields are merged in from $argv[6..].
function record -a profile pid sstatus name cwd
    set -l dir $ROOT/.claude
    test "$profile" = personal; and set dir $ROOT/.claude-personal
    set -l extra '{}'
    test (count $argv) -ge 6; and set extra $argv[6]
    jq -n --argjson pid $pid --arg status $sstatus --arg name $name --arg cwd $cwd \
        --argjson extra $extra '
        {
            pid: $pid, sessionId: "sid-\($pid)", cwd: $cwd, name: $name,
            kind: "interactive", status: $status, version: "2.1.260",
            startedAt: 1788540000000, updatedAt: 1788543000000,
            statusUpdatedAt: 1788543000000, procStart: "\($pid)00"
        } + $extra' >$dir/sessions/$pid.json
end

function collect
    $COLLECT
end

# A record in a config directory the sandbox does not otherwise know about, for
# the tests that hand the collector its own list of accounts.
function record_in -a dir pid sstatus name cwd
    mkdir -p $dir/sessions
    jq -n --argjson pid $pid --arg status $sstatus --arg name $name --arg cwd $cwd '
        {
            pid: $pid, sessionId: "sid-\($pid)", cwd: $cwd, name: $name,
            kind: "interactive", status: $status, version: "2.1.260",
            startedAt: 1788540000000, updatedAt: 1788543000000,
            statusUpdatedAt: 1788543000000, procStart: "\($pid)00"
        }' >$dir/sessions/$pid.json
end

# An OMP session process, the way /proc shows the compiled binary: comm `omp`,
# a working directory, and an fd table to hang transcripts and a tty on.
function fake_omp -a pid starttime cwd
    fake_proc $pid $starttime omp
    echo omp >$AGENT_SESSIONS_PROC/$pid/comm
    string join0 -- omp >$AGENT_SESSIONS_PROC/$pid/cmdline
    mkdir -p $cwd $AGENT_SESSIONS_PROC/$pid/fd
    ln -s $cwd $AGENT_SESSIONS_PROC/$pid/cwd
end

# Point one of an OMP process's fds at a file, as holding it open does.
function omp_holds -a pid fd target
    ln -s $target $AGENT_SESSIONS_PROC/$pid/fd/$fd
end

# An OMP transcript: the title slot, the session header, then the entries given.
function omp_transcript -a file title
    mkdir -p (dirname $file)
    begin
        jq -nc --arg t $title '{type: "title", v: 1, title: $t, source: "auto"}'
        jq -nc '{type: "session", version: 3, id: "ignored", cwd: "/ignored"}'
        printf '%s\n' $argv[3..]
    end >$file
end

function omp_file -a id
    echo $ROOT/.omp/agent/sessions/-proj/2026-10-15T17-07-38-372Z_$id.jsonl
end

function omp_prompt -a text
    jq -nc --arg t $text '{type: "message", timestamp: "2026-10-15T17:00:00.000Z",
                           message: {role: "user", content: [{type: "text", text: $t}]}}'
end

# An assistant turn ending with `stop_reason`; `calls` is a JSON array of
# {id, name, arguments} for a turn that ended asking for tools.
function omp_turn -a stop_reason calls error
    test -n "$calls"; or set calls '[]'
    jq -nc --arg s $stop_reason --argjson calls $calls --arg e "$error" '
        {type: "message", timestamp: "2026-10-15T17:01:40.250Z",
         message: ({role: "assistant", stopReason: $s,
                    content: ([{type: "text", text: "ok"}] + ($calls | map(. + {type: "toolCall"})))}
                   + (if $e == "" then {} else {errorMessage: $e} end))}'
end

function omp_started -a id name command
    jq -nc --arg id $id --arg n $name --arg c "$command" '
        {type: "custom", customType: "tool_execution_start",
         data: ({toolCallId: $id, toolName: $n} + (if $c == "" then {} else {args: {command: $c}} end))}'
end

function omp_answered -a id name
    jq -nc --arg id $id --arg n $name '
        {type: "message", message: {role: "toolResult", toolCallId: $id, toolName: $n,
                                    content: [{type: "text", text: "done"}]}}'
end

echo "═══ Task 1: nothing running ═══"
setup
set -l out (collect)
check "total is zero" 0 (echo $out | jq '.counts.total')
check "sessions is an empty array" 0 (echo $out | jq '.sessions | length')
check "both profile dirs reported present" "work personal" (echo $out | jq -r '.profiles | join(" ")')
check "generatedAt is a millisecond stamp" 13 (echo $out | jq -r '.generatedAt | tostring | length')
# The machine running this suite normally has real sessions of its own. An empty
# sandbox reporting zero is what proves the collector honours $HOME.
check "real sessions on this machine are not reported" 0 (echo $out | jq '.sessions | length')

echo
echo "═══ Task 2: a live session is reported ═══"
setup
record work 4001 busy proj-a /home/u/work/proj-a
fake_proc 4001 400100
set out (collect)
check "one session" 1 (echo $out | jq '.sessions | length')
check "status passed through" busy (echo $out | jq -r '.sessions[0].status')
check "state is working" working (echo $out | jq -r '.sessions[0].state')
check "label is Working" Working (echo $out | jq -r '.sessions[0].label')
check "profile is work" work (echo $out | jq -r '.sessions[0].profile')
check "directory basename extracted" proj-a (echo $out | jq -r '.sessions[0].dir')
check "counted as working" 1 (echo $out | jq '.counts.working')
check "counted in total" 1 (echo $out | jq '.counts.total')

echo
echo "═══ Task 3: dead and recycled pids are dropped ═══"
setup
record work 4002 busy gone /home/u/gone      # no /proc entry at all
record work 4003 busy recycled /home/u/recyc # /proc entry, different start time
fake_proc 4003 999999
record work 4004 idle alive /home/u/alive
fake_proc 4004 400400
set out (collect)
check "only the live session survives" 1 (echo $out | jq '.sessions | length')
check "and it is the right one" alive (echo $out | jq -r '.sessions[0].name')

echo
echo "═══ Task 4: a record with no recorded start time falls back to pid existence ═══"
setup
record work 4005 busy legacy /home/u/legacy '{"procStart": null}'
fake_proc 4005 400500
set out (collect)
check "legacy record kept" 1 (echo $out | jq '.sessions | length')

echo
echo "═══ Task 5: comm containing spaces and parens still parses ═══"
setup
record work 4006 busy weird /home/u/weird
fake_proc 4006 400600 'cla) ude'
set out (collect)
check "start time read from after the last paren" 1 (echo $out | jq '.sessions | length')

echo
echo "═══ Task 6: every status maps to a state, and unknown ones survive ═══"
setup
record work 4010 waiting w /home/u/w '{"waitingFor": "input needed"}'
record work 4011 busy b /home/u/b
record work 4012 shell s /home/u/s
record work 4013 idle i /home/u/i
record work 4014 hibernating h /home/u/h
for pid in 4010 4011 4012 4013 4014
    fake_proc $pid {$pid}00
end
set out (collect)
check "waiting → waiting" waiting (echo $out | jq -r '.sessions[] | select(.pid==4010) | .state')
check "busy → working" working (echo $out | jq -r '.sessions[] | select(.pid==4011) | .state')
check "shell → shell" shell (echo $out | jq -r '.sessions[] | select(.pid==4012) | .state')
check "idle → done" done (echo $out | jq -r '.sessions[] | select(.pid==4013) | .state')
check "idle reads as Done" Done (echo $out | jq -r '.sessions[] | select(.pid==4013) | .label')
check "unrecognised status kept as unknown" unknown (echo $out | jq -r '.sessions[] | select(.pid==4014) | .state')
check "unrecognised status is title-cased for display" Hibernating (echo $out | jq -r '.sessions[] | select(.pid==4014) | .label')
check "counts cover every state" "1 1 1 1 1 5" (echo $out | jq -r '.counts | "\(.waiting) \(.working) \(.shell) \(.done) \(.unknown) \(.total)"')
check "the two worked-out states are counted too, at zero" "0 0" (echo $out | jq -r '.counts | "\(.running) \(.error)"')

echo
echo "═══ Task 7: waiting sessions sort first, newest activity first within a state ═══"
setup
record work 4020 idle old-done /home/u/a '{"statusUpdatedAt": 1788543000000}'
record work 4021 busy older-work /home/u/b '{"statusUpdatedAt": 1788543000000}'
record work 4022 busy newer-work /home/u/c '{"statusUpdatedAt": 1788543999000}'
record work 4023 waiting needs-me /home/u/d '{"statusUpdatedAt": 1788542000000}'
for pid in 4020 4021 4022 4023
    fake_proc $pid {$pid}00
end
set out (collect)
check "order is waiting, newest working, older working, done" \
    "needs-me newer-work older-work old-done" \
    (echo $out | jq -r '[.sessions[].name] | join(" ")')

echo
echo "═══ Task 8: the reason a session is waiting is carried through ═══"
setup
record work 4030 waiting perm /home/u/p '{"waitingFor": "dialog open", "needs": "choose: allow or deny the Bash command"}'
record work 4031 waiting plain /home/u/q '{"waitingFor": "input needed"}'
fake_proc 4030 403000
fake_proc 4031 403100
set out (collect)
check "the specific need wins over the generic one" "choose: allow or deny the Bash command" \
    (echo $out | jq -r '.sessions[] | select(.pid==4030) | .detail')
check "falls back to waitingFor" "input needed" \
    (echo $out | jq -r '.sessions[] | select(.pid==4031) | .detail')

echo
echo "═══ Task 9: both profiles are read ═══"
setup
record work 4040 busy from-work /home/u/w
record personal 4041 idle from-personal /home/u/p
fake_proc 4040 404000
fake_proc 4041 404100
set out (collect)
check "two sessions" 2 (echo $out | jq '.sessions | length')
check "work session labelled work" work (echo $out | jq -r '.sessions[] | select(.pid==4040) | .profile')
check "personal session labelled personal" personal (echo $out | jq -r '.sessions[] | select(.pid==4041) | .profile')

echo
echo "═══ Task 10: a profile that was never created is simply absent ═══"
setup
rm -rf $ROOT/.claude-personal
record work 4050 busy solo /home/u/s
fake_proc 4050 405000
set out (collect)
check "only work reported present" work (echo $out | jq -r '.profiles | join(" ")')
check "session still reported" 1 (echo $out | jq '.sessions | length')

echo
echo "═══ Task 11: junk in the registry never breaks the panel ═══"
setup
record work 4060 busy good /home/u/g
fake_proc 4060 406000
echo -n '{"pid": 4061, "status": "bu' >$ROOT/.claude/sessions/4061.json # torn write
fake_proc 4061 406100
echo '{"pid": 0}' >$ROOT/.claude/sessions/notapid.json # non-numeric name
echo '' >$ROOT/.claude/sessions/4062.json # empty file
fake_proc 4062 406200
# Whole braces around something that is still not JSON: it gets past the shape
# check, so it is the jq that has to drop it - and only it.
echo '{"pid": 4063, "status": "busy",}' >$ROOT/.claude/sessions/4063.json
fake_proc 4063 406300
set out (collect)
check "the healthy session still lands" 1 (echo $out | jq '.sessions | length')
check "and it is the good one" good (echo $out | jq -r '.sessions[0].name')
check "counts agree" 1 (echo $out | jq '.counts.total')

echo
echo "═══ Task 12: a record missing its name falls back to the directory ═══"
setup
record work 4070 busy placeholder /home/u/some/deep/path
jq 'del(.name)' $ROOT/.claude/sessions/4070.json >$ROOT/.claude/sessions/4070.tmp
mv $ROOT/.claude/sessions/4070.tmp $ROOT/.claude/sessions/4070.json
fake_proc 4070 407000
set out (collect)
check "name falls back to the working directory" path (echo $out | jq -r '.sessions[0].name')

echo
echo "═══ Task 13: a busy session running a command reads as Running ═══"
setup
record work 4080 busy runs-a-command /home/u/r
fake_proc 4080 408000
fake_child 4080 40801 bash 'npm test'
record work 4081 busy just-thinking /home/u/t
fake_proc 4081 408100
set out (collect)
check "the one with a child shell is Running" running (echo $out | jq -r '.sessions[] | select(.pid==4080) | .state')
check "and shows what it is running" "npm test" (echo $out | jq -r '.sessions[] | select(.pid==4080) | .detail')
check "the one without stays Working" working (echo $out | jq -r '.sessions[] | select(.pid==4081) | .state')

echo
echo "═══ Task 14: long-lived MCP children are not commands ═══"
setup
record work 4082 busy has-mcp /home/u/m
fake_proc 4082 408200
fake_child 4082 40821 'npm exec @playw' 'irrelevant'
set out (collect)
check "an npm child does not make it Running" working (echo $out | jq -r '.sessions[0].state')

echo
echo "═══ Task 15: only busy sessions are checked for a running command ═══"
setup
record work 4083 idle idle-with-child /home/u/i
fake_proc 4083 408300
fake_child 4083 40831 bash 'stray'
set out (collect)
check "an idle session with a stray child is still Done" done (echo $out | jq -r '.sessions[0].state')

echo
echo "═══ Task 16: an idle session whose last turn failed reads as Error ═══"
setup
record work 4090 idle hit-the-limit /home/u/e
fake_proc 4090 409000
fake_transcript sid-4090 (normal_reply "all good") (api_error "You've hit your session limit · resets 6:40pm")
record work 4091 idle finished-fine /home/u/f
fake_proc 4091 409100
fake_transcript sid-4091 (api_error "an old failure") (normal_reply "recovered since")
set out (collect)
check "the failed one is Error" error (echo $out | jq -r '.sessions[] | select(.pid==4090) | .state')
check "and carries the message" "You've hit your session limit · resets 6:40pm" (echo $out | jq -r '.sessions[] | select(.pid==4090) | .detail')
check "an error it recovered from does not count" done (echo $out | jq -r '.sessions[] | select(.pid==4091) | .state')

echo
echo "═══ Task 17: the transcript scan can be turned off ═══"
setup
record work 4092 idle hit-the-limit /home/u/e
fake_proc 4092 409200
fake_transcript sid-4092 (api_error "You've hit your session limit")
set -gx AGENT_SESSIONS_NO_ERROR 1
set out (collect)
set -e AGENT_SESSIONS_NO_ERROR
check "no transcript is read when disabled" done (echo $out | jq -r '.sessions[0].state')

echo
echo "═══ Task 18: sessions sort by how much they want you ═══"
setup
record work 4100 idle d /home/u/a
record work 4101 busy w /home/u/b
record work 4102 waiting n /home/u/c
record work 4103 shell s /home/u/d
record work 4104 busy r /home/u/e
record work 4105 idle x /home/u/f
for pid in 4100 4101 4102 4103 4104 4105
    fake_proc $pid {$pid}00
end
fake_child 4104 41041 bash 'make'
fake_transcript sid-4105 (api_error "boom")
set out (collect)
check "waiting, error, running, working, shell, done" "n x r w s d" \
    (echo $out | jq -r '[.sessions[].name] | join(" ")')

echo
echo "═══ Task 19: the git repository and branch behind each session ═══"
setup
mkdir -p $ROOT/repo/.git $ROOT/repo/nested/deep $ROOT/plain/dir
echo "ref: refs/heads/feature/thing" >$ROOT/repo/.git/HEAD
record work 4110 busy in-repo $ROOT/repo/nested/deep
record work 4111 busy no-repo $ROOT/plain/dir
fake_proc 4110 411000
fake_proc 4111 411100
set out (collect)
check "repository found by walking up" repo (echo $out | jq -r '.sessions[] | select(.pid==4110) | .repository')
check "branch read from HEAD, slashes and all" feature/thing (echo $out | jq -r '.sessions[] | select(.pid==4110) | .branch')
check "no repository is an empty string, not an error" "" (echo $out | jq -r '.sessions[] | select(.pid==4111) | .repository')
check "and so is the branch" "" (echo $out | jq -r '.sessions[] | select(.pid==4111) | .branch')

echo
echo "═══ Task 20: detached HEAD and worktrees ═══"
setup
mkdir -p $ROOT/detached/.git $ROOT/wt $ROOT/realgit
echo "4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e" >$ROOT/detached/.git/HEAD
record work 4120 busy detached $ROOT/detached
fake_proc 4120 412000
echo "gitdir: $ROOT/realgit" >$ROOT/wt/.git
echo "ref: refs/heads/wt-branch" >$ROOT/realgit/HEAD
record work 4121 busy worktree $ROOT/wt
fake_proc 4121 412100
set out (collect)
check "detached HEAD shows the short sha" 4d5e6f7 (echo $out | jq -r '.sessions[] | select(.pid==4120) | .branch')
check "a worktree follows its gitdir pointer" wt-branch (echo $out | jq -r '.sessions[] | select(.pid==4121) | .branch')

echo
echo "═══ Task 21: a command starting with a dash survives the trip through jq ═══"
setup
record work 4130 busy dashy /home/u/d
fake_proc 4130 413000
fake_child 4130 41301 bash '--color=always grep foo'
set out (collect)
check "the leading dash is not eaten as a jq option" "--color=always grep foo" \
    (echo $out | jq -r '.sessions[0].detail')

echo

echo "═══ Task 22: plan usage reports why a profile has no bars ═══"
setup
set -gx AGENT_USAGE_FIXTURE $ROOT/usage.json
echo '{"limits": []}' >$ROOT/usage.json
# work has no credentials at all; personal has a token that expired in 2001.
jq -n '{claudeAiOauth: {accessToken: "t", expiresAt: 1000000000000}}' >$ROOT/.claude-personal/.credentials.json
set -l out ($USAGE)
check "a profile with no credentials is absent" absent (echo $out | jq -r '.profiles[] | select(.name=="work") | .state')
check "a profile whose token expired says so" expired (echo $out | jq -r '.profiles[] | select(.name=="personal") | .state')
check "neither offers any bars" "0 0" (echo $out | jq -r '[.profiles[].bars | length] | join(" ")')

echo
echo "═══ Task 23: the limits the plan reports become the bars on offer ═══"
setup
set -gx AGENT_USAGE_FIXTURE $ROOT/usage.json
jq -n '{limits: [
        {kind: "session", percent: 11, severity: "normal", resets_at: "2026-09-08T16:30:00Z", is_active: true},
        {kind: "weekly_all", percent: 5, severity: "normal", resets_at: "2026-09-10T16:00:00Z", is_active: false},
        {kind: "weekly_scoped", percent: 0, severity: "normal", resets_at: null, is_active: false,
         scope: {model: {display_name: "Fable"}}}]}' >$ROOT/usage.json
jq -n '{claudeAiOauth: {accessToken: "t", expiresAt: 99999999999999}}' >$ROOT/.claude/.credentials.json
set out ($USAGE)
check "the profile reads ok" ok (echo $out | jq -r '.profiles[] | select(.name=="work") | .state')
check "one bar per limit, named for what it is" "session weekly scoped:Fable" \
    (echo $out | jq -r '[.profiles[] | select(.name=="work") | .bars[].id] | join(" ")')
check "with the labels the popup shows" "Session Weekly Fable" \
    (echo $out | jq -r '[.profiles[] | select(.name=="work") | .bars[].label] | join(" ")')
check "percentages carried through" "11 5 0" \
    (echo $out | jq -r '[.profiles[] | select(.name=="work") | .bars[].percent] | join(" ")')
check "and which one is actually counting" true \
    (echo $out | jq -r '.profiles[] | select(.name=="work") | .bars[0].active')

echo
echo "═══ Task 24: a plan that reports no limits is not an error ═══"
setup
set -gx AGENT_USAGE_FIXTURE $ROOT/usage.json
echo '{"limits": []}' >$ROOT/usage.json
jq -n '{claudeAiOauth: {accessToken: "t", expiresAt: 99999999999999}}' >$ROOT/.claude/.credentials.json
set out ($USAGE)
check "still ok, just empty" ok (echo $out | jq -r '.profiles[] | select(.name=="work") | .state')
check "no bars" 0 (echo $out | jq -r '.profiles[] | select(.name=="work") | .bars | length')
set -e AGENT_USAGE_FIXTURE

echo
echo "═══ Task 25: a failed request is an error, not an empty plan ═══"
setup
set -gx AGENT_USAGE_FIXTURE $ROOT/usage.json
jq -n '{claudeAiOauth: {accessToken: "t", expiresAt: 99999999999999}}' >$ROOT/.claude/.credentials.json
# What the API actually returns when it rate-limits you. It parses cleanly and
# has no `limits` key, so without a type check it read as "this plan has no
# limits" - the widget would quietly show nothing instead of saying it failed.
echo '{"error": {"type": "rate_limit_error", "message": "rate limited"}}' >$ROOT/usage.json
set -l out ($USAGE)
check "an error body is reported as an error" error (echo $out | jq -r '.profiles[] | select(.name=="work") | .state')
check "and offers no bars" 0 (echo $out | jq -r '.profiles[] | select(.name=="work") | .bars | length')
echo '{"limits": []}' >$ROOT/usage.json
set out ($USAGE)
check "a real but empty limits array is still ok" ok (echo $out | jq -r '.profiles[] | select(.name=="work") | .state')
set -e AGENT_USAGE_FIXTURE

echo
echo "═══ Task 26: the accounts read are the ones configured ═══"
setup
set -g FIND $REPO/package/contents/scripts/claude-find-profiles
record work 4260 busy from-stock /home/u/a
record_in $ROOT/.claude-side 4261 idle from-side /home/u/b
record_in $ROOT/.claude-ignored 4262 idle never-asked-for /home/u/c
fake_proc 4260 426000
fake_proc 4261 426100
fake_proc 4262 426200
# A tilde, a name with a space in it, and one directory that does not exist.
set -gx CLAUDE_PROFILES '[{"name":"day job","dir":"~/.claude"},
                          {"name":"side project","dir":"'$ROOT'/.claude-side"},
                          {"name":"gone","dir":"'$ROOT'/.nowhere"}]'
set out (collect)
check "only the configured accounts are read" 2 (echo $out | jq '.sessions | length')
check "a directory nobody asked for stays out" "" (echo $out | jq -r '.sessions[] | select(.pid==4262) | .name')
check "the configured name is what a session carries" "day job" (echo $out | jq -r '.sessions[] | select(.pid==4260) | .profile')
check "a name with a space survives" "side project" (echo $out | jq -r '.sessions[] | select(.pid==4261) | .profile')
check "the tilde is expanded" $ROOT/.claude (echo $out | jq -r '.sessions[] | select(.pid==4260) | .profileDir')
check "the second account carries its own directory" $ROOT/.claude-side (echo $out | jq -r '.sessions[] | select(.pid==4261) | .profileDir')
# Which matters because it is the difference between `claude --resume` and
# CLAUDE_CONFIG_DIR=... claude --resume, and setting that to ~/.claude is the one
# thing Claude Code documents as never to do.
check "only the stock directory is the default one" true (echo $out | jq -r '.sessions[] | select(.pid==4260) | .profileDefault')
check "a second account is not the default one" false (echo $out | jq -r '.sessions[] | select(.pid==4261) | .profileDefault')
check "an account that does not exist is simply absent" "day job side project" (echo $out | jq -r '.profiles | join(" ")')
set -e CLAUDE_PROFILES

echo
echo "═══ Task 27: nothing configured still reads the stock directory ═══"
setup
set -e CLAUDE_PROFILES
record work 4270 busy stock-only /home/u/a
record personal 4271 busy not-asked-for /home/u/b
fake_proc 4270 427000
fake_proc 4271 427100
set out (collect)
# One account, and the one Claude Code itself uses. The old fallback also read
# ~/.claude-personal, which is a path this project's sibling invented rather
# than one anybody else would have.
check "the fallback finds the stock account" 1 (echo $out | jq '.sessions | length')
check "and only that one" stock-only (echo $out | jq -r '.sessions[0].name')
check "named for what it is" default (echo $out | jq -r '.sessions[0].profile')

echo
echo "═══ Task 28: finding accounts under a path ═══"
setup
mkdir -p $ROOT/.claude-side $ROOT/.claude-empty $ROOT/Documents
echo '{}' >$ROOT/.claude/.claude.json
jq -n '{claudeAiOauth: {accessToken: "x"}}' >$ROOT/.claude-side/.credentials.json
# The stock profile keeps its .claude.json beside ~/.claude rather than inside
# it, so home carries the marker without being an account.
echo '{}' >$ROOT/.claude.json
set found ($FIND $ROOT)
check "both marked directories are found" "$ROOT/.claude $ROOT/.claude-side" (echo $found | jq -r '[.[].dir] | join(" ")')
check "the stock directory is named for what it is" default (echo $found | jq -r '.[] | select(.dir=="'$ROOT'/.claude") | .name')
check "a sibling is named after its suffix" side (echo $found | jq -r '.[] | select(.dir=="'$ROOT'/.claude-side") | .name')
check "a directory with no marker is not an account" 0 (echo $found | jq '[.[] | select(.dir | test("empty|Documents"))] | length')
check "home itself is never an account" 0 (echo $found | jq '[.[] | select(.dir == "'$ROOT'")] | length')
check "pointing at one account returns just it" "$ROOT/.claude-side" ($FIND $ROOT/.claude-side | jq -r '[.[].dir] | join(" ")')
check "pointing at anything else returns nothing" 0 ($FIND $ROOT/Documents | jq 'length')
check "a trailing slash on home changes nothing" 0 ($FIND $ROOT/ | jq '[.[] | select(.dir == "'$ROOT'")] | length')

echo
echo "═══ Task 29: plan usage follows the configured accounts ═══"
setup
mkdir -p $ROOT/.claude-side
jq -n '{claudeAiOauth: {accessToken: "t", expiresAt: 99999999999999}}' >$ROOT/.claude/.credentials.json
jq -n '{claudeAiOauth: {accessToken: "t", expiresAt: 99999999999999}}' >$ROOT/.claude-side/.credentials.json
echo '{"limits": [{"kind": "session", "percent": 7, "is_active": true}]}' >$ROOT/usage.json
set -gx AGENT_USAGE_FIXTURE $ROOT/usage.json
set -gx CLAUDE_PROFILES '[{"name":"day job","dir":"'$ROOT'/.claude"},{"name":"side project","dir":"'$ROOT'/.claude-side"}]'
set out ($USAGE)
check "one entry per configured account" 2 (echo $out | jq '.profiles | length')
# The directory is the identity - two accounts may well be called the same
# thing - and the name is only what the footer prints.
check "each is identified by its directory" "$ROOT/.claude $ROOT/.claude-side" (echo $out | jq -r '[.profiles[].id] | join(" ")')
check "and carries the name it was given" "day job side project" (echo $out | jq -r '[.profiles[].name] | join(" ")')
set -e CLAUDE_PROFILES
set -e AGENT_USAGE_FIXTURE

echo
echo "═══ Task 30: no accounts means no accounts ═══"
setup
record work 4300 busy would-show /home/u/a
fake_proc 4300 430000
# Every account switched off, or the last one removed. The fallback must not
# answer that with ~/.claude: "nothing configured" and "configured down to
# nothing" are different answers, and only the first one wants a guess.
set -gx CLAUDE_PROFILES '[]'
set out (collect)
check "no sessions are reported" 0 (echo $out | jq '.sessions | length')
check "and no accounts" 0 (echo $out | jq '.profiles | length')
echo '{"limits": [{"kind": "session", "percent": 7, "is_active": true}]}' >$ROOT/usage.json
set -gx AGENT_USAGE_FIXTURE $ROOT/usage.json
check "plan usage has nothing to report either" 0 ($USAGE | jq '.profiles | length')
set -e AGENT_USAGE_FIXTURE
set -e CLAUDE_PROFILES

echo
echo "═══ Task 31: OMP sessions are found from the process table ═══"
setup
echo "btime 1760000000" >$AGENT_SESSIONS_PROC/stat
fake_omp 4310 12345 $ROOT/code/checkout
omp_transcript (omp_file 01a1-live) (string join '' \UF072C ' FLOW: Fix checkout') (omp_prompt "go")
omp_holds 4310 69 (omp_file 01a1-live)
# The same process holds its subagents' transcripts open too, named for the agent.
omp_transcript $ROOT/.omp/agent/sessions/-proj/2026-10-15T17-07-38-372Z_01a1-live/0-Scout.jsonl sub
omp_holds 4310 70 $ROOT/.omp/agent/sessions/-proj/2026-10-15T17-07-38-372Z_01a1-live/0-Scout.jsonl
# One of OMP's helper processes, which carries the same name.
fake_omp 4311 12346 $ROOT/code/checkout
string join0 -- /usr/bin/omp __omp_worker_js_eval_process >$AGENT_SESSIONS_PROC/4311/cmdline
omp_holds 4311 5 (omp_file 01a1-live)
# OMP installed as a script and run by bun.
fake_omp 4312 12347 $ROOT/code/other
echo bun >$AGENT_SESSIONS_PROC/4312/comm
string join0 -- bun $ROOT/.bun/bin/omp >$AGENT_SESSIONS_PROC/4312/cmdline
omp_transcript (omp_file 01a1-bun) "" (omp_turn stop)
omp_holds 4312 9 (omp_file 01a1-bun)
# Any other bun program is not OMP.
fake_omp 4313 12348 $ROOT/code/other
echo bun >$AGENT_SESSIONS_PROC/4313/comm
string join0 -- bun run dev >$AGENT_SESSIONS_PROC/4313/cmdline
omp_holds 4313 9 (omp_file 01a1-bun)
set out (collect)
check "the session and the bun-run one, and no helper or stranger" "4310 4312" \
    (echo $out | jq -r '[.sessions[] | select(.agent == "omp") | .pid] | sort | join(" ")')
check "the session id comes from the transcript it holds open" 01a1-live \
    (echo $out | jq -r '.sessions[] | select(.pid==4310) | .sessionId')
check "named by its title, without the icon a panel font cannot draw" "FLOW: Fix checkout" \
    (echo $out | jq -r '.sessions[] | select(.pid==4310) | .name')
check "an untitled one is named for its directory" other \
    (echo $out | jq -r '.sessions[] | select(.pid==4312) | .name')
check "the directory is the process's own" $ROOT/code/checkout \
    (echo $out | jq -r '.sessions[] | select(.pid==4310) | .cwd')
check "the account is OMP, from its stock agent directory" "OMP $ROOT/.omp/agent true" \
    (echo $out | jq -r '.sessions[] | select(.pid==4310) | "\(.profile) \(.profileDir) \(.profileDefault)"')
check "the transcript is carried, for the resume command" (omp_file 01a1-live) \
    (echo $out | jq -r '.sessions[] | select(.pid==4310) | .sessionFile')
# Boot time plus 12345 ticks of 10 ms.
check "uptime starts when the process did" 1760000123450 \
    (echo $out | jq -r '.sessions[] | select(.pid==4310) | .startedAt')
# What ending it checks first: the start time, in ticks, as /proc has it.
check "and its start is carried for the end button to check" 12345 \
    (echo $out | jq -r '.sessions[] | select(.pid==4310) | .procStart')

echo
echo "═══ Task 32: an OMP transcript says what its session is doing ═══"
setup
set -l bash_call '[{"id": "t1", "name": "bash", "arguments": {"command": "npm test"}}]'
set -l ask_call '[{"id": "t2", "name": "ask", "arguments": {"questions": [{"id": "db", "question": "Which  database?"}]}}]'
set -l read_call '[{"id": "t3", "name": "read", "arguments": {"path": "a.txt"}}]'
set -l bookkeeping '{"type": "model_usage", "purpose": "title"}' '{"type": "title_change", "title": "x"}'
set -l cases \
    4320 working (omp_prompt "go") \
    4321 running (omp_turn toolUse $bash_call) (omp_started t1 bash "npm   test") \
    4322 waiting (omp_turn toolUse $ask_call) (omp_started t2 ask) \
    4323 working (omp_turn toolUse $read_call) (omp_started t3 read) \
    4324 working (omp_turn toolUse $bash_call) (omp_started t1 bash "npm test") (omp_answered t1 bash) \
    4325 done (omp_turn stop) $bookkeeping \
    4326 done (omp_prompt "go") (omp_turn aborted) \
    4327 error (omp_turn error '' "429 rate limited · retry in 30s") \
    4328 done (omp_turn stop) '{"type": "reset_boundary"}' \
    4329 done
set -l pids
set -l wants
set -l i 1
while test $i -le (count $cases)
    set -l pid $cases[$i]
    set -a pids $pid
    set -a wants $cases[(math $i + 1)]
    set -l entries
    set i (math $i + 2)
    while test $i -le (count $cases); and not string match -qr '^43[0-9]{2}$' -- $cases[$i]
        set -a entries $cases[$i]
        set i (math $i + 1)
    end
    fake_omp $pid {$pid}00 $ROOT/code/s$pid
    omp_transcript (omp_file id-$pid) "" $entries
    omp_holds $pid 7 (omp_file id-$pid)
end
set out (collect)
check "prompt, bash, ask, other tool, answered, stop, interrupt, failure, /clear, empty" \
    (string join ' ' $wants) \
    (for pid in $pids; echo $out | jq -r ".sessions[] | select(.pid==$pid) | .state"; end | string join ' ')
check "a running command is shown, on one line" "npm test" \
    (echo $out | jq -r '.sessions[] | select(.pid==4321) | .detail')
check "a question is shown" "Which database?" \
    (echo $out | jq -r '.sessions[] | select(.pid==4322) | .detail')
check "and so is the error" "429 rate limited · retry in 30s" \
    (echo $out | jq -r '.sessions[] | select(.pid==4327) | .detail')
check "OMP sessions sort and count with the rest" 10 (echo $out | jq '.counts.total')

echo
echo "═══ Task 33: an OMP session with nothing open is found through its terminal ═══"
setup
mkdir -p $ROOT/.omp/agent/terminal-sessions
# Resumed, and has not written since: no fd, but its terminal's breadcrumb.
fake_omp 4330 433000 $ROOT/code/resumed
ln -s /dev/pts/7 $AGENT_SESSIONS_PROC/4330/fd/0
omp_transcript (omp_file 01a1-resumed) "Resumed one" (omp_turn stop)
printf '%s\n' $ROOT/code/resumed (omp_file 01a1-resumed) "cwdstat 1 2" >$ROOT/.omp/agent/terminal-sessions/pts-7
# A breadcrumb left by an earlier session in another directory says nothing
# about the one running in that terminal now.
fake_omp 4331 433100 $ROOT/code/elsewhere
ln -s /dev/pts/8 $AGENT_SESSIONS_PROC/4331/fd/0
printf '%s\n' $ROOT/code/before (omp_file 01a1-before) >$ROOT/.omp/agent/terminal-sessions/pts-8
set out (collect)
check "the breadcrumb names the session" "01a1-resumed Resumed one" \
    (echo $out | jq -r '.sessions[] | select(.pid==4330) | "\(.sessionId) \(.name)"')
check "a breadcrumb for another directory is not trusted" "" \
    (echo $out | jq -r '.sessions[] | select(.pid==4331) | .pid')

echo
echo "═══ Task 34: a named OMP profile is its own account ═══"
setup
set -l side $ROOT/.omp/profiles/side/agent/sessions/-proj/2026-10-15T17-07-38-372Z_01a1-side.jsonl
fake_omp 4340 434000 $ROOT/code/side
omp_transcript $side "" (omp_turn stop)
omp_holds 4340 7 $side
set out (collect)
check "named for the profile, and not the stock directory" "OMP side side false" \
    (echo $out | jq -r '.sessions[0] | "\(.profile) \(.ompProfile) \(.profileDefault)"')
check "its agent directory is the account's" $ROOT/.omp/profiles/side/agent \
    (echo $out | jq -r '.sessions[0].profileDir')
echo
echo "═══ Task 35: OMP switched off is OMP not looked at ═══"
setup
record work 4350 busy claude-one /home/u/a
fake_proc 4350 435000
fake_omp 4351 435100 $ROOT/code/omp-one
omp_transcript (omp_file 01a1-off) "" (omp_turn stop)
omp_holds 4351 7 (omp_file 01a1-off)
set -gx AGENT_SESSIONS_OMP 0
set out (collect)
set -e AGENT_SESSIONS_OMP
check "no OMP session is reported" "4350" (echo $out | jq -r '[.sessions[].pid] | join(" ")')
set out (collect)
check "and on again, it is" "4350 4351" (echo $out | jq -r '[.sessions[].pid] | sort | join(" ")')

echo
echo "═══ Task 36: what OMP costs has a ceiling ═══"
setup
for n in (seq 4360 4393)
    fake_omp $n {$n}00 $ROOT/code/many
    omp_transcript (omp_file id-$n) "" (omp_turn stop)
    omp_holds $n 7 (omp_file id-$n)
end
set out (collect)
check "34 sessions running, 32 read" 32 (echo $out | jq '[.sessions[] | select(.agent == "omp")] | length')

setup
# A transcript that is one 3 MB line: only its first 4 KiB and its last
# 128 KiB are ever read, so it costs what any other does.
fake_omp 4394 439400 $ROOT/code/huge
mkdir -p (dirname (omp_file 01a1-huge))
string repeat -n 3000000 x >(omp_file 01a1-huge)
omp_holds 4394 7 (omp_file 01a1-huge)
# A breadcrumb naming something that is not a transcript is not followed.
mkdir -p $ROOT/.omp/agent/terminal-sessions
fake_omp 4395 439500 $ROOT/code/odd
ln -s /dev/pts/9 $AGENT_SESSIONS_PROC/4395/fd/0
echo "not a transcript" >$ROOT/notes.txt
printf '%s\n' $ROOT/code/odd $ROOT/notes.txt >$ROOT/.omp/agent/terminal-sessions/pts-9
set out (collect)
check "a transcript with no newline is still one session" "huge done" \
    (echo $out | jq -r '.sessions[] | select(.pid==4394) | "\(.name) \(.state)"')
check "a breadcrumb pointing elsewhere reads nothing" "" \
    (echo $out | jq -r '.sessions[] | select(.pid==4395) | .pid')

echo
echo "═══ Task 37: plan usage asks omp about its own logins, inside a cap ═══"
setup
set -e CLAUDE_PROFILES
set -gx CLAUDE_PROFILES '[]'
mkdir -p $ROOT/.omp/agent $ROOT/.omp/profiles/side/agent $ROOT/bin $ROOT/run/systemd
# A systemd user manager, as far as the collector can tell: its socket.
python3 -c "import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])" $ROOT/run/systemd/private
set -gx XDG_RUNTIME_DIR $ROOT/run
# A systemd-run that writes down how it was asked, then runs what follows `--`.
printf '%s\n' '#!/usr/bin/env -S fish --no-config' \
    'echo $argv >>'$ROOT'/systemd-run.log' \
    'set -l i (contains -i -- -- $argv)' \
    'set -l command $argv[(math $i + 1)..]' \
    'exec $command' >$ROOT/bin/systemd-run
# An omp that writes down its arguments and where it was run, then prints
# whatever report the test left for it.
printf '%s\n' '#!/usr/bin/env -S fish --no-config' \
    'echo (pwd) $argv >>'$ROOT'/omp.log' \
    'test -f '$ROOT'/report.json; or exit 1' \
    'cat '$ROOT'/report.json' >$ROOT/bin/omp
chmod +x $ROOT/bin/systemd-run $ROOT/bin/omp
set -gx AGENT_USAGE_SYSTEMD_RUN $ROOT/bin/systemd-run
set -gx AGENT_USAGE_OMP_BIN $ROOT/bin/omp
jq -n '{reports: [
    {provider: "anthropic", metadata: {accountId: "acct-1", email: "a@example.com"},
     limits: [
        {id: "anthropic:5h", label: "Claude 5 Hour", window: {resetsAt: 1792182000000},
         amount: {usedFraction: 0.04, unit: "percent"}},
        {id: "anthropic:7d", label: "Claude 7 Day", window: {resetsAt: 1792684800000},
         amount: {usedFraction: 0.19, unit: "percent"}},
        {id: "anthropic:7d:fable", label: "Claude 7 Day (Fable)", window: {resetsAt: null},
         amount: {usedFraction: 0, unit: "percent"}}]},
    {provider: "openai-codex", metadata: {accountId: "codex-1"}, limits: []}],
  accountsWithoutUsage: [], disabledCredentials: []}' >$ROOT/report.json
set out ($USAGE)
check "one row per agent directory's Anthropic login, named like its sessions" "OMP:ok OMP side:ok" \
    (echo $out | jq -r '[.profiles[] | "\(.name):\(.state)"] | join(" ")')
check "identified by agent directory and account" "omp:$ROOT/.omp/agent#acct-1" \
    (echo $out | jq -r '.profiles[0].id')
check "limits use the same ids as Claude Code's" "session=4 weekly=19 scoped:Fable=0" \
    (echo $out | jq -r '[.profiles[0].bars[] | "\(.id)=\(.percent)"] | join(" ")')
check "and say when they reset" 2026-10-16T20:20:00Z (echo $out | jq -r '.profiles[0].bars[0].resetsAt')
check "only Anthropic accounts become rows" 2 (echo $out | jq '.profiles | length')
check "omp runs inside a scope capped at 512 MB, no swap and 64 tasks" \
    "--user --scope --quiet --collect -p MemoryMax=512M -p MemorySwapMax=0 -p TasksMax=64 --" \
    (string match -r -- '^.*-- ' (head -n 1 $ROOT/systemd-run.log) | string trim)
check "asked for Anthropic only, with no extensions, away from any project" \
    "/ usage --json --provider anthropic --no-extensions" (head -n 1 $ROOT/omp.log)
check "a named profile is asked with --profile" \
    "/ --profile side usage --json --provider anthropic --no-extensions" (sed -n 2p $ROOT/omp.log)

rm $ROOT/report.json
set out ($USAGE)
check "omp failing is one error row per agent directory" "omp:$ROOT/.omp/agent:error" \
    (echo $out | jq -r '.profiles[0] | "\(.id):\(.state)"')
echo 'not json at all' >$ROOT/report.json
set out ($USAGE)
check "and so is omp saying something that is not a report" "error error" \
    (echo $out | jq -r '[.profiles[].state] | join(" ")')
echo '{"reports": [], "accountsWithoutUsage": [], "disabledCredentials": [
    {"provider": "anthropic", "accountId": "acct-2", "email": "b@example.com"}]}' >$ROOT/report.json
rm -rf $ROOT/.omp/profiles
set out ($USAGE)
check "a login omp has disabled reads as signed out" "omp:$ROOT/.omp/agent#acct-2 expired" \
    (echo $out | jq -r '.profiles[0] | "\(.id) \(.state)"')
echo '{"reports": [], "accountsWithoutUsage": [], "disabledCredentials": []}' >$ROOT/report.json
check "no Anthropic login in OMP is no row" 0 ($USAGE | jq '.profiles | length')

rm -f $ROOT/omp.log
set -gx AGENT_USAGE_OMP 0
check "switched off, there is no OMP row" 0 ($USAGE | jq '.profiles | length')
set -e AGENT_USAGE_OMP
check "and omp is never started" no (test -e $ROOT/omp.log; and echo yes; or echo no)

# No systemd user manager: nothing can hold omp to a ceiling, so it is not run.
rm $ROOT/run/systemd/private
set out ($USAGE)
check "without the cap, omp is not run" no (test -e $ROOT/omp.log; and echo yes; or echo no)
check "and the row says why" uncapped (echo $out | jq -r '.profiles[0].state')
set -e AGENT_USAGE_OMP_BIN
set -e AGENT_USAGE_SYSTEMD_RUN
set -e XDG_RUNTIME_DIR
set -e CLAUDE_PROFILES


echo
echo "═══ Task 38: each session says its model and how full its context is ═══"
setup
# The newest main-thread reply counts; a subagent's, and the entry Claude Code
# writes itself for an API error, come after it and say nothing about the session.
function cc_reply -a model input created read
    jq -nc --arg m $model --argjson i $input --argjson c $created --argjson r $read '
        {type: "assistant", isSidechain: false,
         message: {model: $m, role: "assistant", content: [{type: "text", text: "ok"}],
                   usage: {input_tokens: $i, cache_creation_input_tokens: $c,
                           cache_read_input_tokens: $r, output_tokens: 99}}}'
end
record work 4095 idle modelled /home/u/m
fake_proc 4095 409500
fake_transcript sid-4095 (cc_reply claude-opus-4-5 10 20 1000) (cc_reply claude-opus-5-5 2 600 113000) \
    (cc_reply claude-haiku-5-5 1 1 1 | jq -c '.isSidechain = true') \
    (api_error "overloaded" | jq -c '.message.model = "<synthetic>"')
record work 4096 busy fresh /home/u/f
fake_proc 4096 409600
fake_omp 4380 12350 $ROOT/code/omp
omp_transcript (omp_file 01a1-ctx) "" \
    (jq -nc '{type: "model_change", model: "anthropic/claude-opus-4-8"}') \
    (omp_turn stop | jq -c '.message += {model: "claude-opus-4-8",
                                         usage: {input: 5, cacheRead: 40000, cacheWrite: 300, output: 70}}') \
    (jq -nc '{type: "model_change", model: "anthropic/claude-fable-5-1"}')
omp_holds 4380 9 (omp_file 01a1-ctx)
set out (collect)
check "the model of the newest main-thread reply" claude-opus-5-5 \
    (echo $out | jq -r '.sessions[] | select(.pid==4095) | .model')
check "its prompt as sent, cached or not, is the context in use" 113602 \
    (echo $out | jq -r '.sessions[] | select(.pid==4095) | .contextTokens')
check "a session with no reply yet has neither" ":0" \
    (echo $out | jq -r '.sessions[] | select(.pid==4096) | "\(.model):\(.contextTokens)"')
check "an OMP session names the model it switched to since" anthropic/claude-fable-5-1 \
    (echo $out | jq -r '.sessions[] | select(.pid==4380) | .model')
check "and keeps the tokens of its last reply" 40305 \
    (echo $out | jq -r '.sessions[] | select(.pid==4380) | .contextTokens')

echo
echo "═══ Task 39: Codex's plan usage says whether there is anything to read ═══"
setup
set -gx CLAUDE_PROFILES '[]'
check "no Codex home, no Codex row" 0 ($USAGE | jq '.profiles | length')
mkdir -p $ROOT/.codex/sessions
set out ($USAGE)
check "a Codex home with no login is one row, not signed in" "codex:$ROOT/.codex codex Codex absent 0" \
    (echo $out | jq -r '.profiles[] | "\(.id) \(.agent) \(.name) \(.state) \(.bars | length)"')
echo '{}' >$ROOT/.codex/auth.json
check "signed in, but no reply has brought a reading yet" "unread 0" \
    ($USAGE | jq -r '.profiles[] | "\(.state) \(.bars | length)"')
set -e CLAUDE_PROFILES

# A transcript under sessions/<day>, written at `mtime`, holding the lines given.
function codex_rollout -a day name mtime
    mkdir -p $ROOT/.codex/sessions/$day
    printf '%s\n' $argv[4..] >$ROOT/.codex/sessions/$day/rollout-$name.jsonl
    touch -d $mtime $ROOT/.codex/sessions/$day/rollout-$name.jsonl
end

# The token_count event Codex writes with every reply, with the plan's two
# windows as given (JSON, or null).
function codex_limits -a primary secondary
    jq -nc --argjson p $primary --argjson s $secondary '
        {timestamp: "2026-10-30T20:23:24.560Z", type: "event_msg",
         payload: {type: "token_count", info: {total_token_usage: {input_tokens: 1}},
                   rate_limits: {limit_id: "codex", limit_name: null, primary: $p,
                                 secondary: $s, credits: null, plan_type: "plus"}}}'
end

echo
echo "═══ Task 40: Codex's bars come from the newest reading on disk ═══"
setup
set -gx CLAUDE_PROFILES '[]'
mkdir -p $ROOT/.codex
echo '{}' >$ROOT/.codex/auth.json
set -l user (jq -nc '{type: "response_item", payload: {type: "message", role: "user",
                      content: [{type: "input_text", text: "what is \"rate_limits\":{ for?"}]}}')
# An older transcript, with a reading of its own that is out of date.
codex_rollout 2026/10/29 old "2026-10-29 09:00" \
    (codex_limits '{"used_percent": 99, "window_minutes": 43200, "resets_at": 4102444800}' null)
# The newest one with a reading: its last reading wins over its first.
codex_rollout 2026/10/30 current "2026-10-30 12:00" \
    (codex_limits '{"used_percent": 90, "window_minutes": 300, "resets_at": 4102444800}' null) \
    (codex_limits '{"used_percent": 12.4, "window_minutes": 300, "resets_at": 4102444800}' \
        '{"used_percent": 57.6, "window_minutes": 10080, "resets_at": 4102448400}') \
    $user
# Newer still, but no reply yet, so nothing to read in it.
codex_rollout 2026/10/30 fresh "2026-10-30 13:00" \
    (jq -nc '{type: "session_meta", payload: {id: "fresh"}}') $user
set out ($USAGE)
check "signed in with a reading is ok" ok (echo $out | jq -r '.profiles[0].state')
check "one bar per window, primary first, rounded, named as Claude Code's are" \
    "session:Session:12 weekly:Weekly:58" \
    (echo $out | jq -r '[.profiles[0].bars[] | "\(.id):\(.label):\(.percent)"] | join(" ")')
check "and say when they reset" "2100-01-01T00:00:00Z 2100-01-01T01:00:00Z" \
    (echo $out | jq -r '[.profiles[0].bars[].resetsAt] | join(" ")')

# A month-long window at its limit, and a window whose reset has gone by since
# the reading was taken: it has started over, whatever the reading said.
codex_rollout 2026/10/31 later "2026-10-31 08:00" \
    (codex_limits '{"used_percent": 100, "window_minutes": 43200, "resets_at": 4102444800}' \
        '{"used_percent": 40, "window_minutes": 120, "resets_at": 1000000000}')
set out ($USAGE)
check "a monthly window, and one of any other length named by its hours" \
    "monthly:Monthly window:120:2-hour" \
    (echo $out | jq -r '[.profiles[0].bars[] | "\(.id):\(.label)"] | join(" ")')
check "a window at its limit is the active one" "true false" \
    (echo $out | jq -r '[.profiles[0].bars[].active] | join(" ")')
check "a window that has reset since reads empty, with nothing to count down to" "0 null" \
    (echo $out | jq -r '.profiles[0].bars[1] | "\(.percent) \(.resetsAt)"')
codex_rollout 2026/11/01 days "2026-11-01 08:00" \
    (codex_limits null '{"used_percent": 3, "window_minutes": 2880, "resets_at": 4102444800}')
check "a missing window is no bar, and a long one is named by its days" "window:2880:2-day:3" \
    ($USAGE | jq -r '[.profiles[0].bars[] | "\(.id):\(.label):\(.percent)"] | join(" ")')
set -e CLAUDE_PROFILES

echo
echo "═══ Task 41: each usage row says which agent holds the login, and Codex can be left out ═══"
setup
set -gx AGENT_USAGE_FIXTURE $ROOT/usage.json
echo '{"limits": [{"kind": "session", "percent": 7, "is_active": true}]}' >$ROOT/usage.json
jq -n '{claudeAiOauth: {accessToken: "t", expiresAt: 99999999999999}}' >$ROOT/.claude/.credentials.json
mkdir -p $ROOT/.codex
echo '{}' >$ROOT/.codex/auth.json
codex_rollout 2026/10/30 one "2026-10-30 12:00" \
    (codex_limits '{"used_percent": 1, "window_minutes": 300, "resets_at": 4102444800}' null)
check "Claude Code's accounts first, then Codex's" "claude:work claude:personal codex:Codex" \
    ($USAGE | jq -r '[.profiles[] | "\(.agent):\(.name)"] | join(" ")')
set -gx AGENT_USAGE_CODEX 0
check "switched off, there is no Codex row" "claude claude" \
    ($USAGE | jq -r '[.profiles[].agent] | join(" ")')
set -e AGENT_USAGE_CODEX
set -e AGENT_USAGE_FIXTURE

echo
echo "═══ Task 42: a Codex TUI is a session, and its thread says how it stands ═══"
# Codex 0.166 as it lays itself out: a process whose comm is `codex`, and a
# rollout per thread under ~/.codex/sessions/YYYY/MM/DD whose first line says
# which app wrote it, where, and when the thread began. The clock is pinned:
# boot at 1760000000, so a TUI at 100000 ticks started 2025-10-09T09:10:00Z, and
# 1000 s of uptime for children to be aged against.
function fake_codex -a pid starttime cwd
    fake_proc $pid $starttime codex
    echo codex >$AGENT_SESSIONS_PROC/$pid/comm
    string join0 -- /usr/bin/codex $argv[4..-1] >$AGENT_SESSIONS_PROC/$pid/cmdline
    mkdir -p $cwd $AGENT_SESSIONS_PROC/$pid/fd
    ln -sfn $cwd $AGENT_SESSIONS_PROC/$pid/cwd
end
function codex_clock
    echo "btime 1760000000" >$AGENT_SESSIONS_PROC/stat
    echo "1000.00 4000.00" >$AGENT_SESSIONS_PROC/uptime
end
# A thread's rollout with its first line; prints the path. `extra` is merged
# into the first line's payload, and `home` stands in for ~/.codex.
function cx_thread -a id cwd created originator extra home
    test -n "$originator"; or set originator codex-tui
    test -n "$extra"; or set extra '{}'
    test -n "$home"; or set home $ROOT/.codex
    mkdir -p $home/sessions/2025/10/09
    set -l file $home/sessions/2025/10/09/rollout-2025-10-09T06-10-01-$id.jsonl
    jq -nc --arg id $id --arg cwd $cwd --arg t $created --arg o $originator --argjson x $extra '
        {timestamp: $t, ordinal: 0, type: "session_meta",
         payload: ({session_id: $id, id: $id, timestamp: $t, cwd: $cwd,
                    originator: $o, cli_version: "0.166.0", source: "cli",
                    thread_source: "user", model_provider: "openai"} + $x
                   + {base_instructions: {text: "You are a coding agent."}})}' >$file
    echo $file
end
# One rollout line, written `ago` seconds before now.
function cx_line -a ago type payload
    jq -nc --arg t (date -u -d @(math (date +%s) - $ago) +%FT%T.000Z) --arg ty $type \
        --argjson p $payload '{timestamp: $t, type: $ty, payload: $p}'
end
# A tool call in code mode, the way gpt-5.6 makes them: a script calling tools.
function cx_exec -a ago call_id code
    cx_line $ago response_item (jq -nc --arg id $call_id --arg c $code \
        '{type: "custom_tool_call", status: "completed", call_id: $id, name: "exec", input: $c}')
end
# A child of `holder` that started `age_ms` ago, with the argv given after comm.
function cx_child -a holder kid age_ms comm
    mkdir -p $AGENT_SESSIONS_PROC/$holder/task/$holder
    echo -n "$kid " >>$AGENT_SESSIONS_PROC/$holder/task/$holder/children
    fake_proc $kid (math "(1000000 - $age_ms) / 10") $comm
    echo $comm >$AGENT_SESSIONS_PROC/$kid/comm
    string join0 -- $argv[5..-1] >$AGENT_SESSIONS_PROC/$kid/cmdline
end
function cx_turn_done
    cx_line 60 turn_context '{"cwd":"/x","model":"gpt-5.6-luna","approval_policy":"on-request"}'
    cx_line 60 event_msg '{"type":"task_started","model_context_window":258400}'
    cx_line 50 event_msg '{"type":"token_count","info":{"last_token_usage":{"total_tokens":16992},"model_context_window":258400},"rate_limits":null}'
    cx_line 50 event_msg '{"type":"task_complete","last_agent_message":"Done.","error":null}'
end
setup
codex_clock
fake_codex 5001 100000 $ROOT/code/api
set -l t1 01a10000-0000-7000-8000-000000000001
set -l f (cx_thread $t1 $ROOT/code/api 2025-10-09T09:10:01.000Z)
cx_turn_done >>$f
ln -s $f $AGENT_SESSIONS_PROC/5001/fd/40
# The session index is append-only: the newest name is the one in force.
echo '{"id":"'$t1'","thread_name":"Explore the API","updated_at":"2025-10-09T09:11:00Z"}' >>$ROOT/.codex/session_index.jsonl
echo '{"id":"'$t1'","thread_name":"Fix the login","updated_at":"2025-10-09T09:12:00Z"}' >>$ROOT/.codex/session_index.jsonl
set out (collect)
check "the TUI is the session" "5001 codex" (echo $out | jq -r '.sessions[] | "\(.pid) \(.agent)"')
check "a finished turn is done" done (echo $out | jq -r '.sessions[0].state')
check "named by the newest entry in the session index" "Fix the login" (echo $out | jq -r '.sessions[0].name')
check "resumable by its thread id" $t1 (echo $out | jq -r '.sessions[0].sessionId')
check "its model, and the context Codex itself measures" "gpt-5.6-luna 16992 258400" \
    (echo $out | jq -r '.sessions[0] | "\(.model) \(.contextTokens) \(.contextWindow)"')
check "the stock home, signalled by the TUI's own start" "Codex true 100000 0.166.0" \
    (echo $out | jq -r '.sessions[0] | "\(.profile) \(.profileDefault) \(.procStart) \(.version)"')

echo
echo "═══ Task 43: what Codex is doing is read off its open tool calls ═══"
setup
codex_clock
# One TUI per state, each running its own thread, all in one collect.
function cx_session -a pid n
    fake_codex $pid 100000 $ROOT/code/s$n
    set -l file (cx_thread 01a10000-0000-7000-8000-00000000010$n $ROOT/code/s$n 2025-10-09T09:10:01.000Z)
    ln -s $file $AGENT_SESSIONS_PROC/$pid/fd/40
    cx_line 30 event_msg '{"type":"task_started","model_context_window":258400}' >>$file
    echo $file
end
set f (cx_session 5101 1)
cx_line 20 event_msg '{"type":"task_complete","error":{"message":"You\'ve hit your usage limit.","codex_error_info":"usage_limit_exceeded"}}' >>$f
set f (cx_session 5102 2)
cx_line 20 response_item '{"type":"custom_tool_call_output","call_id":"a","output":"aborted by user after 3.0s"}' >>$f
cx_line 20 event_msg '{"type":"turn_aborted","reason":"interrupted","error":null}' >>$f
set f (cx_session 5103 3)
cx_line 20 response_item '{"type":"message","role":"assistant","content":[]}' >>$f
set f (cx_session 5104 4)
cx_exec 3 c4 'const r = await tools.exec_command({cmd: "sleep 20 && touch done.txt", workdir: "/tmp"});' >>$f
cx_child 5104 51041 4000 codex-code-mode /usr/bin/codex-code-mode-host
cx_child 5104 51042 2500 bash /usr/bin/bash -c "sleep 20 && touch done.txt"
# Sandboxed: bwrap around a script that ends by exec-ing the command.
set f (cx_session 5105 5)
cx_line 4 response_item '{"type":"function_call","call_id":"c5","name":"exec_command","arguments":"{\\"cmd\\":\\"cargo test\\"}"}' >>$f
cx_child 5105 51051 3500 bwrap bwrap --argv0 codex-linux-sandbox -- /usr/bin/codex --apply-seccomp-then-exec -- \
    /usr/bin/bash -c "export PATH='/usr/bin'

exec '/usr/bin/bash' -c 'cargo test'"
# Asked to leave the sandbox, and nothing has started for it: an approval prompt.
set f (cx_session 5106 6)
cx_exec 5 c6 'const r = await tools.exec_command({cmd: "curl -sI https://example.com", sandbox_permissions: "require_escalated"});' >>$f
cx_child 5106 51061 4000 codex-code-mode /usr/bin/codex-code-mode-host
# The same, a moment after it was written: the command may yet start.
set f (cx_session 5107 7)
cx_exec 0 c7 'const r = await tools.exec_command({cmd: "curl -sI https://example.com", sandbox_permissions: "require_escalated"});' >>$f
set f (cx_session 5108 8)
cx_line 2 response_item '{"type":"function_call","call_id":"c8","name":"request_user_input","arguments":"{\\"questions\\":[{\\"question\\":\\"Which database?\\"}]}"}' >>$f
set f (cx_session 5109 9)
cx_exec 9 c9 'const r = await tools.exec_command({cmd: "ls"});' >>$f
cx_line 8 response_item '{"type":"custom_tool_call_output","call_id":"c9","output":[]}' >>$f
set -g cx_out (collect)
function cx_state -a pid
    echo $cx_out | jq -r --argjson p $pid '.sessions[] | select(.pid == $p) | "\(.state)|\(.detail)"'
end
check "a failed turn is an error, with Codex's message" "error|You've hit your usage limit." (cx_state 5101)
check "Esc ends the turn: done" "done|" (cx_state 5102)
check "an open turn with nothing pending is working" "working|" (cx_state 5103)
check "a command a child is running is running, and named" "running|sleep 20 && touch done.txt" (cx_state 5104)
check "a sandboxed one is found through its wrapper" "running|cargo test" (cx_state 5105)
check "an escalation nothing has started for is waiting on you" \
    "waiting|approve: curl -sI https://example.com" (cx_state 5106)
check "but not in the moment before it starts" "working|" (cx_state 5107)
check "a question for you is waiting, and asked" "waiting|Which database?" (cx_state 5108)
check "an answered call is not pending" "working|" (cx_state 5109)

echo
echo "═══ Task 44: threads in Codex's shared app-server go to the TUI that made them ═══"
setup
codex_clock
# The daemon runs threads for every plain `codex`, and keeps one open after its
# TUI quits. Two TUIs in one directory, started 09:10 and 09:20, and one
# resuming an older thread by id.
fake_codex 5200 50000 $ROOT app-server --listen unix://
fake_codex 5201 100000 $ROOT/code/shared
fake_codex 5202 160000 $ROOT/code/shared
fake_codex 5203 200000 $ROOT/code/shared resume 01a10000-0000-7000-8000-000000000205
fake_codex 5204 200000 $ROOT/code/shared exec "summarise the repo"
set -l n 1
for spec in 201:09:10:01 202:09:20:02 203:09:05:00 205:08:00:00
    set -l parts (string split -m1 : $spec)
    set f (cx_thread 01a10000-0000-7000-8000-000000000$parts[1] $ROOT/code/shared 2025-10-09T$parts[2].000Z)
    cx_turn_done >>$f
    ln -s $f $AGENT_SESSIONS_PROC/5200/fd/4$n
    set n (math $n + 1)
end
# A bare `codex resume` opens the picker, so its thread began long before it -
# but it is the only claim on that directory's thread.
fake_codex 5205 200000 $ROOT/code/older resume
set f (cx_thread 01a10000-0000-7000-8000-000000000206 $ROOT/code/older 2025-10-08T17:00:00.000Z)
cx_turn_done >>$f
ln -s $f $AGENT_SESSIONS_PROC/5200/fd/49
set out (collect)
check "each TUI has its own thread; the quit TUI's and `codex exec` show nothing" \
    "5201:201 5202:202 5203:205 5205:206" \
    (echo $out | jq -r '[.sessions[] | select(.agent == "codex") | "\(.pid):\(.sessionId[-3:])"] | sort | join(" ")')

echo
echo "═══ Task 45: only a terminal's own thread is a Codex session ═══"
setup
codex_clock
# An editor's app-server thread, and a subagent's rollout held beside its
# parent's, newer than it.
fake_codex 5300 50000 $ROOT app-server --analytics-default-enabled
fake_codex 5301 100000 $ROOT/code/x
set f (cx_thread 01a10000-0000-7000-8000-000000000300 $ROOT/code/x 2025-10-09T09:10:01.000Z codex_vscode)
cx_turn_done >>$f
ln -s $f $AGENT_SESSIONS_PROC/5300/fd/40
set f (cx_thread 01a10000-0000-7000-8000-000000000301 $ROOT/code/x 2025-10-09T09:10:01.000Z)
cx_turn_done >>$f
ln -s $f $AGENT_SESSIONS_PROC/5301/fd/40
set f (cx_thread 01a10000-0000-7000-8000-000000000302 $ROOT/code/x 2025-10-09T09:12:00.000Z codex-tui \
    '{"parent_thread_id":"01a10000-0000-7000-8000-000000000301","thread_source":"subagent"}')
cx_line 1 event_msg '{"type":"task_started"}' >>$f
ln -s $f $AGENT_SESSIONS_PROC/5301/fd/41
record work 4500 busy claude-one /home/u/a
fake_proc 4500 450000
set out (collect)
check "the TUI shows its own thread, not the editor's or a subagent's" "5301:301:done" \
    (echo $out | jq -r '[.sessions[] | select(.agent == "codex") | "\(.pid):\(.sessionId[-3:]):\(.state)"] | join(" ")')
set -gx AGENT_SESSIONS_CODEX 0
set out (collect)
set -e AGENT_SESSIONS_CODEX
check "switched off, no Codex session is reported" "4500" (echo $out | jq -r '[.sessions[].pid] | join(" ")')

echo
echo "═══ Task 46: another Codex home is its own account ═══"
setup
codex_clock
fake_codex 5401 100000 $ROOT/code/y
set f (cx_thread 01a10000-0000-7000-8000-000000000401 $ROOT/code/y 2025-10-09T09:10:01.000Z codex-tui '{}' $ROOT/.codex-work)
cx_turn_done >>$f
ln -s $f $AGENT_SESSIONS_PROC/5401/fd/40
set out (collect)
check "named for its directory, and not the stock one" "Codex codex-work false $ROOT/.codex-work" \
    (echo $out | jq -r '.sessions[0] | "\(.profile) \(.profileDefault) \(.profileDir)"')

echo
echo "═══ Tripwire: the real session registry was untouched ═══"
set -g HOME $REAL_HOME
set -l leaked (__registry_records $REAL_HOME | string match -r '40[0-9]{2}\.json' | string join ' ')
check "no sandbox pid was written to the real registry" "" "$leaked"
# A record going missing is only suspicious if its session is still running.
# Claude Code removes its own record when a session exits, and sessions exit
# while this suite runs - the first version of this check flagged that as a leak
# and failed for a reason that had nothing to do with the code under test.
check "no live session lost its record" "" (
    for f in (string split ' ' -- "$REAL_BEFORE")
        test -n "$f"; or continue
        # Both profiles, because the snapshot covers both - looking only in the
        # work profile reported every personal session as a deleted record.
        test -e $REAL_HOME/.claude/sessions/$f; and continue
        test -e $REAL_HOME/.claude-personal/sessions/$f; and continue
        set -l gone_pid (string replace -r '\.json$' '' -- $f)
        test -d /proc/$gone_pid; and echo $f
    end | string join ' ')

echo
echo "════════════════════════════"
echo "PASS: $PASS  FAIL: $FAIL"
rm -rf (dirname $ROOT)
test $FAIL -eq 0
