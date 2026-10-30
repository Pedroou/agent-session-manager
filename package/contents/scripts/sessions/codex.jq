# Turn Codex's TUIs and threads into session records, for agent-sessions.
# Run as `jq -ncR -f codex.jq --argjson now <epoch-ms> --arg home <~/.codex>`.
#
# stdin, one line each, every control record led by U+001D and its fields split
# by U+001F (neither can occur raw inside JSON text, so no transcript line is
# ever mistaken for one):
#
#   P pid ticks started cwd resume picker repository branch   - a TUI
#   I <session_index.jsonl line>                              - a thread's name
#
# and then, for each thread, a line holding only U+001E, followed by
#
#   T holder-pid rollout-path codex-home
#   M <the rollout's first line, to 4 KiB>
#   C age-ms argv-tail                                        - per child of the holder
#   <the tail of the rollout>
#
# `now` is the wall clock and a child's age counts from boot, so a tool call is
# compared with a child by how long ago each began, never by clock time.
#
# Prints one record per TUI that has a thread, in pid order.

def flat: gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");

# "2026-10-30T20:23:24.560Z" as epoch milliseconds, or 0.
def isoms:
    if type != "string" then 0 else
        (try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 * 1000) catch 0) as $s
        | (try (capture("\\.(?<f>[0-9]+)Z$").f + "00" | .[0:3] | tonumber) catch 0) as $f
        | if $s > 0 then $s + $f else 0 end
    end;

# A JSON string field out of a line that may be cut short, unescaped.
def field($key):
    [match("\"" + $key + "\":\"((?:[^\"\\\\]|\\\\.)*)\""; "g") | .captures[0].string]
    | map(try ("\"" + . + "\"" | fromjson) catch null);

# A string as the shell would single-quote it: how a sandboxed command's
# wrapper script ends.
def shq: "'" + gsub("'"; "'\\''") + "'";

# What a tool call runs. Arguments are JSON for a plain function call; in code
# mode the model writes a script instead (`tools.exec_command({cmd: "..."})`),
# and the command is taken from it when it is written as a string literal.
def callText: .payload | (.arguments // .input // .action // "") | if type == "string" then . else tojson end;
def callCommand:
    .payload as $p
    | if $p.type == "function_call" then
          (try ($p.arguments | fromjson) catch {}) as $a
          | if ($a.cmd | type) == "string" then $a.cmd
            elif ($a.command | type) == "array" then
                ($a.command | if length == 3 and (.[1] == "-lc" or .[1] == "-c") then .[2] else join(" ") end)
            elif ($a.command | type) == "string" then $a.command
            else null end
      elif $p.type == "local_shell_call" then
          ($p.action.command // null | if type == "array" then join(" ") else . end)
      elif $p.type == "custom_tool_call" then
          ([($p.input // "") | match("[\"']?\\bcmd[\"']?\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\")"; "g")
            | .captures[0].string | try fromjson catch empty] | first) // null
      else null end;

# The question in a request_user_input call, best effort.
def question:
    ([callText | match("[\"']?\\bquestion[\"']?\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\")"; "g")
      | .captures[0].string | try fromjson catch empty] | first) // "";

# What the thread is doing, from its tail and the holder's children.
#
# The turn markers decide most of it: `task_complete` ends a turn (with `error`
# set when it failed), `turn_aborted` is you pressing Esc, `task_started` opens
# one. In an open turn, a tool call with no output yet is what to look at:
#
#   - a question for you (request_user_input)                -> waiting
#   - a command, and a child of the holder is running it     -> running
#   - it asked to leave the sandbox (require_escalated), no
#     child has started since, and it has had over 1.5 s     -> waiting: approval
#   - polling a background command (write_stdin)             -> running
#   - anything else                                          -> working
#
# Codex writes a call before it asks for approval and before it starts the
# command, and never writes the approval prompt itself - so "waiting" is read
# off the absence of the command, and a call that is merely slow to start reads
# as waiting until it does. Each of these was seen on a live session; nothing
# that was not is guessed at.
def state($entries; $children):
    [$entries | to_entries[]
     | select(.value.type == "event_msg"
              and (.value.payload.type | IN("task_started", "task_complete", "turn_aborted")))]
    | last as $mark
    | if ($entries | length) == 0 then {status: "idle"}
      elif $mark != null and $mark.value.payload.type == "task_complete" then
          if ($mark.value.payload.error | type) == "object" then
              {status: "error",
               detail: (($mark.value.payload.error.message // "") | tostring | flat | .[0:200])}
          else {status: "idle"} end
      elif $mark != null and $mark.value.payload.type == "turn_aborted" then {status: "idle"}
      else
          # An open turn - or one so long its start is beyond the tail.
          $entries[(if $mark == null then 0 else $mark.key + 1 end):] as $turn
          | [$turn[] | select(.type == "response_item"
                              and (.payload.type | IN("function_call_output", "custom_tool_call_output")))
             | .payload.call_id] as $answered
          | ([$turn[] | select(.type == "response_item"
                               and (.payload.type | IN("function_call", "custom_tool_call", "local_shell_call")))
              | select(.payload.call_id as $id | ($answered | index([$id])) == null)]
             | last) as $call
          | if $call == null then {status: "busy"} else
                ($call | callText) as $text
                | ($call | callCommand) as $cmd
                | ($now - ($call.timestamp | isoms)) as $age
                | ([$children[] | select(.age >= 0 and .age <= $age + 200)] | length > 0) as $newer
                | (if $cmd == null then false else
                       ($cmd | flat) as $c
                       | ($c | shq | flat) as $q
                       | $c != "" and any($children[]; (.cmd | flat) as $tail
                                          | ($tail | endswith($c)) or ($tail | endswith($q)))
                   end) as $runs
                | if ($call.payload.name == "request_user_input" or ($text | test("\\brequest_user_input\\s*\\("))) then
                      {status: "waiting", detail: ($call | question | flat | .[0:200])}
                  elif $runs then
                      {status: "running", detail: ($cmd | flat | .[0:120])}
                  elif ($text | test("require_escalated")) and ($newer | not) and $age > 1500 then
                      {status: "waiting",
                       detail: (if $cmd == null then "approve a command"
                                else "approve: " + ($cmd | flat | .[0:120]) end)}
                  elif ($text | test("\\bwrite_stdin\\b")) and ($children | length > 0) then
                      {status: "running", detail: ""}
                  else {status: "busy"} end
            end
      end;

# The model, the tokens the last request carried, and the window Codex itself
# measures them against.
def context($entries):
    {model: ([$entries[] | select(.type == "turn_context") | .payload.model | strings] | last // ""),
     contextTokens: ([$entries[] | select(.type == "event_msg" and .payload.type == "token_count")
                      | .payload.info.last_token_usage.total_tokens | numbers] | last // 0),
     contextWindow: ([$entries[] | select(.type == "event_msg")
                      | .payload.info.model_context_window // .payload.model_context_window
                      | numbers] | last // 0)};

# Read the stream.
(reduce inputs as $line ({tuis: [], names: {}, threads: []};
    if $line == "\u001e" then .threads += [{children: [], lines: []}]
    elif ($line | startswith("\u001d")) then
        ($line[1:] | split("\u001f")) as $f
        | if $f[0] == "P" then
              .tuis += [{pid: ($f[1] | tonumber), ticks: $f[2], started: ($f[3] | tonumber),
                         cwd: $f[4], resume: $f[5], picker: ($f[6] == "1"),
                         repository: $f[7], branch: $f[8]}]
          elif $f[0] == "I" then
              (try ($f[1:] | join("\u001f") | fromjson) catch null) as $e
              | if ($e | type) == "object" and ($e.id | type) == "string"
                then .names[$e.id] = ($e.thread_name // "") else . end
          elif ($line | length) > 0 and (.threads | length) > 0 then
              if $f[0] == "T" then
                  .threads[-1] += {holder: ($f[1] | tonumber), path: $f[2], home: $f[3]}
              elif $f[0] == "M" then .threads[-1].meta = ($f[1:] | join("\u001f"))
              elif $f[0] == "C" then
                  .threads[-1].children += [{age: ($f[1] | tonumber? // -1),
                                             cmd: ($f[2:] | join("\u001f"))}]
              else . end
          else . end
    elif (.threads | length) > 0 then .threads[-1].lines += [$line]
    else . end)) as $in

# Each thread's facts. It began when its TUI created it - the timestamp inside
# the first line's payload, the second one on the line - which for a new thread
# is the moment its TUI finished starting.
| [$in.threads[] | select(.path != null)
   | (.meta // "") as $m
   | [.lines[] | try fromjson catch null | objects] as $entries
   | {holder, path, home, children,
      id: ((.path | capture("-(?<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(_[^/]*)?\\.jsonl$").id) // ""),
      cwd: (($m | field("cwd"))[0] // ""),
      created: ((($m | field("timestamp")) as $t | $t[1] // $t[0]) | isoms),
      version: (($m | field("cli_version"))[0] // ""),
      entries: $entries,
      last: (($entries | last // {}) | .timestamp | isoms)}] as $threads

# Which thread is which TUI's, in order of how sure it is:
#   1. `codex resume <id>` names it;
#   2. a TUI that holds rollouts itself runs those;
#   3. a thread in a shared app-server belongs to the TUI in its directory that
#      started last before the thread began - a TUI creates its thread as it
#      starts, and a later /new is still that TUI's latest in that directory;
#   4. a TUI that opened the resume picker takes a thread in its directory that
#      no one else has, since that thread began before the TUI did.
# A thread no TUI claims is one its TUI has quit from, which the app-server
# keeps open - not a session. Of several threads, a TUI shows the latest active.
| [$in.tuis[] | .pid] as $tuiPids
| [$threads[] | .holder] as $holders
| [$in.tuis[] | .resume | select(. != "")] as $named
# The TUI a shared app-server's thread belongs to by rule 3, as a pid or null.
# A TUI that runs its own threads never uses the app-server, so it is no rival.
| def owner($th):
    [$in.tuis[] | select(.cwd == $th.cwd and .started <= $th.created + 2000
                         and (.pid | IN($holders[]) | not))]
    | max_by(.started) | .pid;
  [$in.tuis[] as $t
   | {tui: $t,
      threads: [$threads[] | select(
          ($t.resume != "" and .id == $t.resume)
          or .holder == $t.pid
          or ((.holder | IN($tuiPids[]) | not) and (.id | IN($named[]) | not)
              and owner(.) == $t.pid))]}]
| ([.[] | .threads[] | .path]) as $claimed
| map(if (.threads | length) == 0 and .tui.picker then
          .tui as $t
          | .threads = [$threads[] | select(.cwd == $t.cwd and (.holder | IN($tuiPids[]) | not)
                                            and (.path | IN($claimed[]) | not))]
      else . end)
| .[]
| select(.threads | length > 0)
| .tui as $t
| (.threads | max_by(.last)) as $th
| state($th.entries; $th.children) as $s
| context($th.entries) as $c
| ($th.home == $home) as $default
| {
    agent:           "codex",
    pid:             $t.pid,
    procStart:       $t.ticks,
    sessionId:       $th.id,
    cwd:             $t.cwd,
    name:            (($in.names[$th.id] // "") | if . == "" then null else . end),
    status:          $s.status,
    detail:          ($s.detail // ""),
    kind:            "interactive",
    version:         $th.version,
    startedAt:       $t.started,
    statusUpdatedAt: (if $th.last > 0 then $th.last else $t.started end),
    model:           $c.model,
    contextTokens:   $c.contextTokens,
    contextWindow:   $c.contextWindow,
    profile:         (if $default then "Codex"
                      else "Codex " + ($th.home | split("/") | last | ltrimstr(".")) end),
    profileDir:      $th.home,
    profileDefault:  $default,
    repository:      $t.repository,
    branch:          $t.branch
  }
