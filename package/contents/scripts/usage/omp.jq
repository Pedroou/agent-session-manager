# Turn `omp usage --json` into the widget's usage profiles, for usage/omp.bash.
# Run as `jq -c --arg group <id> --arg name <label> -f usage/omp.jq`.
#
# OMP owns its logins - it stores them, refreshes them, and asks Anthropic for
# their limits itself - so the widget never sees a token: it reads the report
# OMP prints. Only Anthropic accounts are turned into rows; a plan limit is the
# same measurement whichever tool is spending it, so the bars use the same ids
# as Claude Code's (session, weekly, scoped:<model>) and a limit picked for one
# reads the same on the other.
#
# One row per Anthropic account, one compact object per line, every row tagged
# with $group - the agent directory it came from - so a failed run can keep the
# whole group's last reading. No Anthropic account at all prints nothing. Input
# that is not a usage report is an error, so the caller can tell "nothing to
# show" from "OMP said something else".

def resetIso:
    if type == "number" and . > 0 then (. / 1000 | floor | todate) else null end;

def percent:
    if .amount.usedFraction != null then (.amount.usedFraction * 100 | round)
    elif .amount.unit == "percent" and .amount.used != null then (.amount.used | round)
    else null end;

# "Claude 7 Day (Fable)" is a limit scoped to one model, which Claude Code's
# own endpoint names by the model alone.
def bar:
    (.id // "") as $id
    | ((.label // "") | (capture("\\((?<t>[^()]+)\\)\\s*$") | .t) // null) as $scope
    | percent as $p
    | (.window.resetsAt | resetIso) as $reset
    | (if $id == "anthropic:5h" then {id: "session", label: "Session"}
       elif $id == "anthropic:7d" then {id: "weekly", label: "Weekly"}
       elif $scope != null then {id: ("scoped:" + $scope), label: $scope}
       else {id: $id, label: ((.label // $id) | sub("^Claude "; ""))} end)
    # Severity is left to the percentage: OMP's own status words are not the
    # API's, and guessing at a mapping would colour a bar wrongly.
    + {percent: $p, severity: "", resetsAt: $reset, active: false};

def anthropic: .[]? | objects | select((.provider // "") == "anthropic");
def key($o): ($o.accountId // $o.email // "") | tostring;

if (.reports | type) != "array" then error("not an omp usage report") else
    # Best answer first, so an account that both reported and was listed as
    # failing keeps its bars.
    [ (.reports | anthropic
       | {key: key(.metadata // {}), email: (.metadata.email // ""), state: "ok",
          bars: [(.limits // [])[] | objects | bar | select(.percent != null)]}),
      (.accountsWithoutUsage | anthropic
       | {key: key(.), email: (.email // ""), state: "error", bars: []}),
      (.disabledCredentials | anthropic
       | {key: key(.), email: (.email // ""), state: "expired", bars: []}) ]
    | reduce .[] as $row ([]; if any(.[]; .key == $row.key) then . else . + [$row] end)
    | length as $n
    | .[]
    | {
        id: ($group + "#" + .key),
        group: $group,
        agent: "omp",
        # Two Anthropic logins in one agent directory would otherwise be two
        # rows with the same name.
        name: (if $n > 1 and .email != "" then $name + " · " + .email else $name end),
        state: .state,
        bars: .bars
      }
end
