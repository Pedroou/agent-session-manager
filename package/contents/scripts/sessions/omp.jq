# Turn OMP transcripts into session records, for agent-sessions.
# Run as `jq -ncR -f omp.jq --args <meta>...`.
#
# stdin carries every session in turn: a line holding only a record separator
# (U+001E) opens each one, followed by its transcript's first line and then the
# tail of the transcript. The tail starts mid-line, and OMP may be halfway
# through writing its last line, so any line that is not a whole JSON object is
# dropped.
#
# The positional arguments are twelve per session, in the same order, each with
# the ":" the caller prefixes so that jq never reads one as an option: pid,
# session id, cwd, start time in epoch ms, transcript path, OMP profile name,
# start time in clock ticks since boot, the account as shown, agent directory,
# "true" when that is the stock ~/.omp/agent, repository, branch.
#
# Prints one compact record per session, in order, whatever its transcript held.

def arg($i; $k): ($ARGS.positional[$i * 12 + $k] // ":") | .[1:];
def flat: gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
def ms: (.timestamp // "") | (try (sub("\\.[0-9]+"; "") | fromdateiso8601 * 1000) catch 0);

# What moves a session along. Everything else in a transcript - usage, titles,
# model switches - is bookkeeping that can land after a turn has ended, and must
# not read as the turn still going.
def relevant:
    .type == "message" or .type == "custom_message" or .type == "reset_boundary"
    or (.type == "custom" and .customType == "tool_execution_start");

def toolCalls: [(.message.content // [])[]? | objects | select(.type == "toolCall")];

# The tools the last assistant turn asked for that have started - OMP writes a
# `tool_execution_start` marker the moment each one does - and have no result
# yet. `ask` is a question put to you; bash and eval are a command or a script
# executing. Anything else, a subagent included, is the agent still working.
def toolState($rel; $ai):
    $rel[$ai + 1:] as $after
    | [$after[] | select(.type == "message" and .message.role == "toolResult")
       | .message.toolCallId] as $answered
    | [$after[] | select(.type == "custom") | .data | objects] as $started
    | [$rel[$ai] | toolCalls[]
       | select(.id as $id | any($answered[]; . == $id) | not)
       | . + {start: (.id as $id | [$started[] | select(.toolCallId == $id)] | first)}
       | select(.start != null)] as $live
    | ([$live[] | select(.name == "ask")] | first) as $ask
    | ([$live[] | select(.name == "bash" or .name == "eval")] | first) as $run
    | if $ask != null then
          {status: "waiting",
           detail: ((($ask.arguments.questions // [])[0]?.question
                     // $ask.arguments.question // "") | tostring | flat | .[0:200])}
      elif $run != null then
          {status: "running",
           detail: (($run.start.args.command // $run.arguments.command
                     // $run.start.intent // $run.name) | tostring | flat | .[0:120])}
      else {status: "busy"} end;

def state($entries):
    [$entries[] | select(relevant)] as $rel
    | ([range(0; $rel | length)
        | select($rel[.].type == "message" and $rel[.].message.role == "assistant")]
       | last) as $ai
    | ($rel | last) as $last
    | if $last == null or $last.type == "reset_boundary" then {status: "idle"}
      elif $last.type == "message" and $last.message.role == "assistant" then
          if $last.message.stopReason == "error" then
              {status: "error",
               detail: (($last.message.errorMessage // "") | tostring | flat | .[0:200])}
          elif $last.message.stopReason == "toolUse" then toolState($rel; $ai)
          # stop, length, and aborted: an interrupted turn is a finished one
          else {status: "idle"} end
      elif $last.type == "custom"
           or ($last.type == "message" and $last.message.role == "toolResult") then
          if $ai == null then {status: "busy"} else toolState($rel; $ai) end
      # a `!` command typed at the prompt: no turn follows it
      elif $last.type == "message"
           and ($last.message.role == "bashExecution" or $last.message.role == "pythonExecution") then
          {status: "idle"}
      # a prompt, or a message handed to the agent: a turn is under way
      else {status: "busy"} end
    | . + {at: ($last // {} | ms)};

# The title, minus the icon OMP may put in front of it: a glyph from a
# private-use block, which a panel font has no way to draw.
def title($entries):
    ([$entries[] | select(.type == "title" or .type == "session") | .title | strings] | first // "")
    | sub("^[\\x{E000}-\\x{F8FF}\\x{F0000}-\\x{10FFFD}]+\\s*"; "");

# The model the session is on, and the tokens its last request carried - the
# prompt as sent, cached or not, which is what fills the context window. The
# model is the last one named, by a reply or by a switch made since; the tokens
# come from the last reply, since a switch has not sent anything yet.
def model($entries):
    [$entries[]
     | if .type == "message" and .message.role == "assistant"
          and (.message.usage | type) == "object" then
           {model: .message.model, usage: .message.usage}
       elif .type == "model_change" then {model: .model}
       else empty end] as $named
    | ([$named[] | select(.usage != null)] | last) as $reply
    | {model: (([$named[] | .model | strings] | last) // ""),
       contextTokens: (if $reply == null then 0
                       else ($reply.usage.input // 0) + ($reply.usage.cacheRead // 0)
                            + ($reply.usage.cacheWrite // 0) end)};

reduce inputs as $line ([];
    if $line == "\u001e" then . + [[]] else .[-1] += [$line] end)
| to_entries[]
| .key as $i
| [.value[] | try fromjson catch null | objects] as $entries
| state($entries) as $s
| title($entries) as $title
| model($entries) as $model
| ((arg($i; 3) | tonumber?) // 0) as $startedAt
| {
    agent:           "omp",
    pid:             (arg($i; 0) | tonumber),
    procStart:       arg($i; 6),
    sessionId:       arg($i; 1),
    cwd:             arg($i; 2),
    name:            (if $title == "" then null else $title end),
    status:          $s.status,
    detail:          ($s.detail // ""),
    kind:            "interactive",
    version:         "",
    startedAt:       $startedAt,
    statusUpdatedAt: (if ($s.at // 0) > 0 then $s.at else $startedAt end),
    model:           $model.model,
    contextTokens:   $model.contextTokens,
    profile:         arg($i; 7),
    profileDir:      arg($i; 8),
    profileDefault:  (arg($i; 9) == "true"),
    repository:      arg($i; 10),
    branch:          arg($i; 11),
    # What `omp --resume` needs: the transcript, for one kept outside every
    # agent directory, and the named profile it belongs to.
    sessionFile:     arg($i; 4),
    ompProfile:      arg($i; 5)
  }
