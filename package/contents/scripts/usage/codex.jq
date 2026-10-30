# Turn the newest plan reading in Codex's transcripts into the widget's usage
# row, for usage/codex.bash. Run as `jq -c --arg id <codex:home> -f
# usage/codex.jq` on one transcript line - a `token_count` event, whose
# payload's `rate_limits` is what the plan said with the reply it came with:
#
#   {"limit_id": "codex", "plan_type": "free", "credits": null,
#    "primary":   {"used_percent": 0.0, "window_minutes": 43200,
#                  "resets_at": 1795983536},
#    "secondary": null}
#
# `primary` and `secondary` are the plan's two windows, either of which may be
# missing; each that is there becomes a bar, primary first. A window is named by
# its length, so the five-hour and weekly ones share their ids with Claude
# Code's (session, weekly) and a limit picked for one account means the same on
# the next.
#
# The reading is as old as the last reply, which may be days. A window whose
# reset time has already gone by has started over since, whatever it said then:
# it reads 0%, with no reset time to count down to. Severity is left to the
# percentage, as Codex gives none.
#
# A line that is not a reading is an error, so the caller can say it could not
# read one rather than show an empty plan.

def window($minutes):
    if $minutes == 300 then {id: "session", label: "Session"}
    elif $minutes == 10080 then {id: "weekly", label: "Weekly"}
    elif $minutes == 43200 then {id: "monthly", label: "Monthly"}
    elif $minutes < 1440 then {id: "window:\($minutes)", label: "\($minutes / 60 | round)-hour"}
    else {id: "window:\($minutes)", label: "\($minutes / 1440 | round)-day"} end;

def bar:
    (.used_percent // 0) as $used
    | (.resets_at | if type == "number" and . > 0 then floor else null end) as $resets
    | ($resets != null and $resets <= now) as $over
    | window(.window_minutes // 0 | floor)
    + {percent: (if $over then 0 else ($used | round) end),
       severity: "",
       resetsAt: (if $over or $resets == null then null else ($resets | todate) end),
       active: (($over | not) and $used >= 100)};

.payload.rate_limits as $limits
| if ($limits | type) != "object" then error("not a Codex plan reading") else
    {id: $id, group: $id, agent: "codex", name: "Codex", state: "ok",
     bars: [$limits.primary, $limits.secondary | objects | bar]}
end
