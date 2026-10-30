# Turn Claude Code's registry records into session records, for agent-sessions.
# Run as `jq -ncR -f claude.jq --args <meta>...`.
#
# stdin carries every session in turn: a line holding only a record separator
# (U+001E) opens each one, followed by its registry record on one line and then
# up to four assistant lines of its transcript, newest first.
#
# The positional arguments are seven per session, in the same order, each with
# the ":" the caller prefixes so that jq never reads one as an option: profile
# name, the state worked out from /proc or the transcript (running, error, or ""
# for none), what goes with it, repository, branch, profile directory, and
# "true" when that directory is the stock ~/.claude.
#
# Prints one compact line per session, in order: its record, or null when the
# registry record only looked like JSON.

def arg($i; $k): ($ARGS.positional[$i * 7 + $k] // ":") | .[1:];

# The model the session is on, and how much of its context the last turn used:
# both on the newest assistant entry of the main thread, which carries the model
# id and the request's token counts. A subagent's entries and the ones Claude
# Code writes itself (model "<synthetic>", for an API error) say nothing about
# the session's own context, so they are passed over.
def context($lines):
    ([$lines[] | try fromjson catch null | objects
      | select(.type == "assistant" and .isSidechain != true
               and (.message.usage | type) == "object"
               and ((.message.model // "") | startswith("<") | not))]
     | first) as $m
    | if $m == null then {model: "", contextTokens: 0} else
        {model: ($m.message.model // ""),
         contextTokens: (($m.message.usage.input_tokens // 0)
                         + ($m.message.usage.cache_creation_input_tokens // 0)
                         + ($m.message.usage.cache_read_input_tokens // 0))}
      end;

reduce inputs as $line ([];
    if $line == "\u001e" then . + [[]] else .[-1] += [$line] end)
| to_entries[]
| .key as $i
| .value as $lines
| (($lines[0] // "") | try fromjson catch null) as $r
| if ($r | type) != "object" then null else
    context($lines[1:]) as $c
    # The two states worked out from /proc and the transcript stand in for the
    # registry status; everything downstream treats them alike.
    | arg($i; 1) as $overlay
    | {
        agent:           "claude",
        pid:             ($r.pid // 0),
        procStart:       (($r.procStart // "") | tostring),
        sessionId:       ($r.sessionId // ""),
        cwd:             ($r.cwd // ""),
        name:            $r.name,
        status:          (if $overlay != "" then $overlay else ($r.status // "") end),
        detail:          (if arg($i; 2) != "" then arg($i; 2)
                          else ($r.needs // $r.waitingFor // "") end),
        kind:            ($r.kind // "interactive"),
        version:         ($r.version // ""),
        startedAt:       ($r.startedAt // 0),
        statusUpdatedAt: ($r.statusUpdatedAt // $r.updatedAt // 0),
        model:           $c.model,
        contextTokens:   $c.contextTokens,
        profile:         (arg($i; 0) | if . == "" then "work" else . end),
        profileDir:      arg($i; 5),
        profileDefault:  (arg($i; 6) == "true"),
        repository:      arg($i; 3),
        branch:          arg($i; 4)
      }
  end
