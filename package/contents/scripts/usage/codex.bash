# shellcheck shell=bash
# shellcheck disable=SC2154 # $__au_rows and $__au_lib are set outside this
# file: by agent-usage, which sources it.
# Codex's (OpenAI Codex CLI's) plan usage, for agent-usage.
#
# Codex is read rather than asked: every reply it gets comes with the plan's
# limits as they stand, and Codex writes them into that session's transcript -
# a `token_count` event carrying `rate_limits` - so the newest such line on
# disk is the newest reading there is. No request is made and no credential is
# touched; auth.json is only looked at to tell "never signed in" apart.
#
# One row per Codex home, which is ~/.codex and only when it exists: the
# transcripts live under <home>/sessions/YYYY/MM/DD/rollout-*.jsonl, and the
# reading is taken from the most recently written of them that has one. What
# the reading means is codex.jq's.
#
# Its cost has a ceiling however many sessions Codex has kept: one `find`, no
# deeper than the day directories, and of what it finds only the 8 newest
# files are opened, each read backwards only as far as its last reading, with
# that line held to 1 MiB. A reading older than those 8 files is not looked
# for - the row says there is none yet - rather than reading a whole history.

__au_codex_row() {
    jq -nc --arg id "$1" --arg state "$2" \
        '{id: $id, group: $id, agent: "codex", name: "Codex", state: $state, bars: []}'
}

__au_codex_collect() {
    local home=$HOME/.codex entry line=''
    local id=codex:$home
    local -a newest=()
    [[ -d $home ]] || return 0
    if [[ ! -e $home/auth.json ]]; then
        __au_rows+=("$(__au_codex_row "$id" absent)")
        return
    fi

    # Newest first, by modification time: a transcript is appended to with every
    # reply, so the one written last holds the latest reading.
    mapfile -t newest < <(find "$home/sessions" -mindepth 4 -maxdepth 4 -type f \
        -name 'rollout-*.jsonl' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 8)
    for entry in "${newest[@]}"; do
        # `tac` reads from the end, and `grep -m1` stops it at the first hit, so
        # a long transcript costs only its tail. The pattern is the field as
        # Codex writes it: inside any quoted text its quotes would be escaped.
        line=$(tac -- "${entry#* }" 2>/dev/null | grep -m1 -F -- '"rate_limits":{' | head -c 1048576)
        [[ -n $line ]] && break
    done

    if [[ -z $line ]]; then
        __au_rows+=("$(__au_codex_row "$id" unread)")
        return
    fi
    __au_rows+=("$(printf '%s\n' "$line" | jq -c --arg id "$id" -f "$__au_lib/codex.jq" 2>/dev/null ||
        __au_codex_row "$id" error)")
}
