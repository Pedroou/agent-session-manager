# shellcheck shell=bash
# shellcheck disable=SC2154 # $__au_rows and $__au_lib are set outside this
# file: by agent-usage, which sources it.
# OMP's (oh-my-pi's) plan usage, for agent-usage.
#
# OMP is asked rather than read: `omp usage --json` reports its own logins,
# refreshing their tokens as it goes, so the widget never touches OMP's
# credentials at all.
#
# OMP keeps its logins per agent directory: ~/.omp/agent, and one per named
# profile under ~/.omp/profiles. Each is asked once, with `omp usage`, and each
# Anthropic account in its answer becomes a row named the way that agent
# directory's sessions are labelled - "OMP", or "OMP <profile>" (omp.jq).
#
# omp is a 200 MB runtime, so it runs only inside a transient systemd scope
# that the kernel holds to 512 MB of memory, no swap and 64 tasks - if it ever
# wanted more, it alone is killed, inside its scope, and that account reads
# "couldn't get usage" until the next try. It is also stopped after 15 seconds,
# its output is read up to 1 MiB, and nothing is retried. Where there is no
# systemd user manager to hold it to that, omp is not run at all: the row says
# so instead of running something unbounded in the background.

__au_omp_row() {
    jq -nc --arg id "$1" --arg name "$2" --arg state "$3" \
        '{id: $id, group: $id, agent: "omp", name: $name, state: $state, bars: []}'
}

# The omp to run, into __au_omp_bin; empty when there is none.
__au_omp_find_bin() {
    # The panel's $PATH is the session's, which need not include where an
    # installer put omp - so the usual places are tried too.
    local candidate
    local -a candidates=()
    __au_omp_bin=
    candidate=$(type -P omp) && candidates+=("$candidate")
    candidates+=("$HOME/.local/bin/omp" "$HOME/.bun/bin/omp")
    [[ -n $AGENT_USAGE_OMP_BIN ]] && candidates=("$AGENT_USAGE_OMP_BIN")
    for candidate in "${candidates[@]}"; do
        if [[ -x $candidate ]]; then
            __au_omp_bin=$candidate
            return
        fi
    done
}

__au_omp_collect() {
    local dir profile i report rows systemd_run=systemd-run capped=false
    # Agent directories that exist, with the --profile each one needs.
    local -a groups=() labels=() profile_args=() profile_flag=()
    if [[ -d $HOME/.omp/agent ]]; then
        groups+=("omp:$HOME/.omp/agent")
        labels+=(OMP)
        profile_args+=("")
    fi
    for dir in "$HOME"/.omp/profiles/*/agent; do
        [[ -d $dir ]] || continue
        profile=${dir%/agent}
        profile=${profile##*/}
        groups+=("omp:$dir")
        labels+=("OMP $profile")
        profile_args+=("$profile")
    done
    ((${#groups[@]} > 0)) || return 0

    # No omp installed means nothing to ask, whatever ~/.omp holds.
    __au_omp_find_bin
    [[ -n $__au_omp_bin ]] || return 0

    [[ -n $AGENT_USAGE_SYSTEMD_RUN ]] && systemd_run=$AGENT_USAGE_SYSTEMD_RUN
    if command -v "$systemd_run" >/dev/null 2>&1 &&
        [[ -n $XDG_RUNTIME_DIR && -S $XDG_RUNTIME_DIR/systemd/private ]]; then
        capped=true
    fi

    for i in "${!groups[@]}"; do
        if [[ $capped != true ]]; then
            __au_rows+=("$(__au_omp_row "${groups[i]}" "${labels[i]}" uncapped)")
            continue
        fi
        profile_flag=()
        [[ -n ${profile_args[i]} ]] && profile_flag=(--profile "${profile_args[i]}")
        # Away from any project directory, so no project's .omp settings apply.
        # The `cd` happens in the substitution's own subshell, so nothing after
        # this - another agent's collector - is moved.
        report=$(cd / && timeout -k 2 15 "$systemd_run" --user --scope --quiet --collect \
            -p MemoryMax=512M -p MemorySwapMax=0 -p TasksMax=64 -- \
            "$__au_omp_bin" "${profile_flag[@]}" usage --json --provider anthropic --no-extensions \
            </dev/null 2>/dev/null | head -c 1048576)
        if [[ -n $report ]]; then
            rows=$(printf '%s' "$report" | jq -c --arg group "${groups[i]}" --arg name "${labels[i]}" \
                -f "$__au_lib/omp.jq" 2>/dev/null) ||
                rows=$(__au_omp_row "${groups[i]}" "${labels[i]}" error)
        else
            rows=$(__au_omp_row "${groups[i]}" "${labels[i]}" error)
        fi
        __au_rows+=("$rows")
    done
}
