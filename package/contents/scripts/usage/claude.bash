# shellcheck shell=bash
# shellcheck disable=SC2154 # $__au_rows is set outside this file: by
# agent-usage, which sources it.
# Claude Code's plan usage, for agent-usage: one row per configured account.
#
# The percentages behind Claude Code's own /usage view come from an authenticated
# call to the endpoint below, with the bearer token Claude Code already stores per
# profile. Nothing is written and no token is ever logged: it is handed to curl
# through stdin rather than argv, so it does not show up in the process list.
#
# This is a Claude Code internal, not documented API. It is called at most once
# every few minutes - plan limits move slowly - and a failure is reported as a
# state rather than left to look like zero usage.

__au_claude_endpoint=https://api.anthropic.com/api/oauth/usage

__au_claude_row() {
    jq -nc --arg id "$1" --arg name "$2" --arg state "$3" \
        '{id: $id, agent: "claude", name: $name, state: $state, bars: []}'
}

# One profile's bars, or the reason there are none. Prints a JSON object.
__au_claude_profile() {
    local id=$1 name=$2 dir=$3
    local credentials=$dir/.credentials.json

    if [[ ! -r $credentials ]]; then
        __au_claude_row "$id" "$name" absent
        return
    fi

    local token expires
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$credentials" 2>/dev/null)
    expires=$(jq -r '.claudeAiOauth.expiresAt // empty' "$credentials" 2>/dev/null)

    if [[ -z $token ]]; then
        __au_claude_row "$id" "$name" absent
        return
    fi

    # A token past its expiry would just come back 401. Saying so up front is
    # both faster and a better message than "the request failed".
    if [[ -n $expires ]]; then
        local now_ms sign='' magnitude=$expires
        now_ms=$(date +%s)000
        [[ $magnitude == -* ]] && sign=- magnitude=${magnitude#-}
        if [[ $magnitude =~ ^[0-9]{1,18}$ ]] && ((${sign}10#$magnitude < now_ms)); then
            __au_claude_row "$id" "$name" expired
            return
        fi
    fi

    local body
    if [[ -n $AGENT_USAGE_FIXTURE ]]; then
        body=$(cat -- "$AGENT_USAGE_FIXTURE" 2>/dev/null)
    else
        # --config on stdin keeps the token out of argv, where every other
        # process on the machine could read it.
        # --fail matters: without it a 429 or a 500 comes back as a JSON error
        # object, which has no `limits` key and so parsed cleanly as "this plan
        # has no limits" - a rate-limited request looked exactly like an empty
        # plan. With it, curl writes nothing and this reports the failure.
        body=$(printf 'url = "%s"\nheader = "Authorization: Bearer %s"\nheader = "anthropic-beta: oauth-2025-04-20"\nheader = "Content-Type: application/json"\n' \
            "$__au_claude_endpoint" "$token" | curl --silent --show-error --fail --max-time 8 --config - 2>/dev/null)
    fi

    if [[ -z $body ]]; then
        __au_claude_row "$id" "$name" error
        return
    fi

    # `limits[]` already carries percent, severity and reset time per limit, and
    # names the model a scoped limit belongs to - so the bars on offer are
    # whatever the plan actually has, not a hardcoded three.
    printf '%s\n' "$body" | jq -c --arg id "$id" --arg name "$name" '
        # A body with no `limits` array at all is an error object, not a plan
        # without limits; only a real (possibly empty) array counts as ok.
        if (.limits | type) != "array" then
            {id: $id, agent: "claude", name: $name, state: "error", bars: []}
        else
        def barLabel($l):
            if $l.kind == "session" then "Session"
            elif $l.kind == "weekly_all" then "Weekly"
            else ($l.scope.model.display_name // "Scoped") end;
        def barId($l):
            if $l.kind == "session" then "session"
            elif $l.kind == "weekly_all" then "weekly"
            else "scoped:" + ($l.scope.model.display_name // "other") end;

        {
            id: $id,
            agent: "claude",
            name: $name,
            state: "ok",
            bars: [ (.limits // [])[]
                | select(.percent != null)
                | {
                    id: barId(.),
                    label: barLabel(.),
                    percent: (.percent // 0),
                    severity: (.severity // "normal"),
                    resetsAt: .resets_at,
                    active: (.is_active == true)
                  } ]
        } end' 2>/dev/null ||
        __au_claude_row "$id" "$name" error
}

__au_claude_collect() {
    # Which config directories to ask about, and what to call each one. Kept in
    # step with agent-sessions on purpose: the two are read together and a
    # profile the session list knows about but the usage footer does not would
    # be a puzzle.
    local i dir
    local -a flat=() names=() dirs=()
    if [[ -n $CLAUDE_PROFILES ]]; then
        mapfile -t flat < <(printf '%s\n' "$CLAUDE_PROFILES" | jq -r '.[] | (.name // ""), (.dir // "")' 2>/dev/null)
        for ((i = 0; i < ${#flat[@]}; i += 2)); do
            dir=${flat[i + 1]}
            [[ -n $dir ]] || continue
            [[ $dir == '~'* ]] && dir=$HOME${dir:1}
            names+=("${flat[i]}")
            dirs+=("$dir")
        done
    fi
    # Nothing configured: the directory Claude Code keeps its own account in, so
    # running this by hand still shows something. Only that one - any other path
    # is somebody's choice, and guessing at it is what this replaced.
    # Only when nothing was handed over at all. An empty list is an answer -
    # every account turned off, or the last one removed - and answering it with
    # a directory nobody asked for is how "no accounts" became unreachable.
    if ((${#dirs[@]} == 0)) && [[ -z $CLAUDE_PROFILES ]]; then
        names=(default)
        dirs=("$HOME/.claude")
    fi

    for i in "${!dirs[@]}"; do
        __au_rows+=("$(__au_claude_profile "${dirs[i]}" "${names[i]}" "${dirs[i]}")")
    done
}
