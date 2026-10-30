# shellcheck shell=bash
# shellcheck disable=SC2154 # $__as_proc, $__as_lib and every answer common.bash
# hands back are set outside this file: by agent-sessions, which sources it.
# Codex's (OpenAI Codex CLI's) sessions, for agent-sessions.
#
# A Codex session is two things: the TUI in a terminal, which is what the panel
# lists, ends and jumps to; and a thread, whose transcript - a "rollout" at
# <codex-home>/sessions/YYYY/MM/DD/rollout-<time>-<thread-id>.jsonl - says what
# it is doing. The process holding the rollout open is not always the TUI. A
# plain `codex` runs its threads in a shared `codex app-server` daemon, and the
# daemon keeps a thread's rollout open after its TUI has quit; a TUI started
# with configuration flags runs its thread itself. So this finds both kinds of
# process, hands codex.jq every TUI and every thread that could belong to one,
# and codex.jq pairs them up (see "Which thread" there).
#
# What it reads, all from files: each codex process's argv, cwd and fds; the
# first line of each rollout (whose app wrote it, and when the thread began);
# the rollout's tail; the thread names in <codex-home>/session_index.jsonl; and
# the children of whichever process runs the thread's commands, with their age
# and argv, since Codex never writes down that it is waiting for an approval.
#
# A rollout's first line carries Codex's whole system prompt, so it is read to
# 4 KiB, which holds every field used. Threads are capped at 32, and each costs
# one `tail` of 128 KiB, so the one jq they share sees about 4 MiB at most.

# Every codex TUI and every process that may hold a TUI's thread, from the
# process table. The binary is `codex` whichever way it was installed: the npm
# wrapper execs into it on the same pid where Node allows, and otherwise starts
# it as a child, which is the one found.
#
# A process is placed by its first positional argument, skipping the flags that
# take a value. None, `resume` or `fork` - or a prompt - is a TUI. `app-server`
# listening on a unix socket is the daemon TUIs share; an app-server without
# one is an editor's (VS Code's runs over stdio) and holds only the editor's
# threads, so its fds are not even looked at. Any other subcommand is not
# interactive. `resume <thread-id>` names its thread outright, and a bare
# `resume` (the picker) is noted, since its thread began before it did.
#
# Sets __as_codex_tuis (pids), __as_codex_resume (thread id or "" per pid),
# __as_codex_picker (1 or "" per pid) and __as_codex_holders (pids).
__as_codex_procs() {
    local pid arg first want_value i
    local -a args=()
    __as_codex_tuis=()
    __as_codex_holders=()
    __as_codex_resume=()
    __as_codex_picker=()
    __as_proc_table
    for pid in "${!__as_comms[@]}"; do
        [[ ${__as_comms[pid]} == codex ]] || continue
        args=()
        mapfile -t -d '' -n 32 args 2>/dev/null <"$__as_proc/$pid/cmdline" || continue
        ((${#args[@]} > 0)) || continue
        first='' want_value=false
        for ((i = 1; i < ${#args[@]}; i++)); do
            arg=${args[i]}
            if [[ $want_value == true ]]; then
                want_value=false
                continue
            fi
            case $arg in
            -c | --config | -m | --model | -p | --profile | -s | --sandbox | \
                -a | --ask-for-approval | -C | --cd | -i | --image | --add-dir | \
                --enable | --disable | --remote | --remote-auth-token-env)
                want_value=true
                continue
                ;;
            --codex-run-as-*)
                first=helper
                break
                ;;
            -*) continue ;;
            esac
            first=$arg
            break
        done
        case $first in
        app-server)
            for ((i = i + 1; i < ${#args[@]}; i++)); do
                if [[ ${args[i]} == --listen && ${args[i + 1]} == unix://* ]] ||
                    [[ ${args[i]} == --listen=unix://* ]]; then
                    __as_codex_holders+=("$pid")
                    break
                fi
            done
            ;;
        '' | resume | fork)
            __as_codex_tuis+=("$pid")
            __as_codex_resume[pid]=
            __as_codex_picker[pid]=
            if [[ $first == resume ]]; then
                __as_codex_picker[pid]=1
                for ((i = i + 1; i < ${#args[@]}; i++)); do
                    [[ ${args[i]} == -* ]] && continue
                    if [[ ${args[i]} =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                        __as_codex_resume[pid]=${args[i]}
                        __as_codex_picker[pid]=
                    fi
                    break
                done
            fi
            ;;
        exec | e | review | mcp | mcp-server | exec-server | remote-control | \
            agents | queue | login | logout | doctor | sandbox | completion | \
            apply | cloud | features | debug | help | helper) ;;
        *)
            # A prompt given on the command line.
            __as_codex_tuis+=("$pid")
            __as_codex_resume[pid]=
            __as_codex_picker[pid]=
            ;;
        esac
    done
}

# The children of a process, the way codex.jq wants them: one line each, a
# unit-separator-led "C" record with the child's age in milliseconds and the
# end of its last argument. Codex runs a command as `bash -c <command>`, or as
# bwrap around a script that ends `exec '/usr/bin/bash' -c '<command>'` when it
# is sandboxed - so the end of the last argument is where the command is.
# Codex's own helpers (`codex-code-mode-host`, the daemon's pid loop) are not
# commands, and are left out. Appends to __as_codex_children (one string).
__as_codex_children_of() {
    local pid=$1 uptime_ms=$2 f kid comm part last line age
    local -a kids=() seen=()
    __as_codex_children=
    for f in "$__as_proc/$pid/task/"*/children; do
        read -r -a kids 2>/dev/null <"$f" || [[ ${#kids[@]} -gt 0 ]] || continue
        for kid in "${kids[@]}"; do
            [[ $kid =~ ^[0-9]+$ && -z ${seen[kid]} ]] || continue
            seen[kid]=1
            comm=
            IFS= read -r -n 64 comm 2>/dev/null <"$__as_proc/$kid/comm"
            [[ $comm == codex* && $comm != codex-linux-sa* ]] && continue
            __as_start_ticks "$kid" || continue
            age=-1
            ((uptime_ms >= 0)) && age=$((uptime_ms - __as_ticks * 10))
            last=
            while IFS= read -r -d '' -n 131072 part || [[ -n $part ]]; do
                last=$part
            done 2>/dev/null <"$__as_proc/$kid/cmdline"
            ((${#last} > 8192)) && last=${last: -8192}
            last=${last//[$'\n\t\r\v\f']/ }
            printf -v line '\x1dC\x1f%s\x1f%s\n' "$age" "$last"
            __as_codex_children+=$line
        done
    done
}

__as_codex_collect() {
    __as_codex_procs
    local -a tuis=("${__as_codex_tuis[@]:0:32}")
    ((${#tuis[@]} > 0)) || return 0
    local -a holders=("${__as_codex_holders[@]}")

    __as_resolve_all "${tuis[@]}" "${holders[@]}"

    # Milliseconds since boot, to age a child process by, and the wall clock,
    # to age a tool call by. Both are durations, so a boot time that has drifted
    # (a suspend, a clock step) does not skew the comparison codex.jq makes.
    local uptime_ms=-1 up=
    if IFS=' ' read -r up _ 2>/dev/null <"$__as_proc/uptime" && [[ $up =~ ^([0-9]+)\.([0-9]{2})$ ]]; then
        uptime_ms=$((10#${BASH_REMATCH[1]} * 1000 + 10#${BASH_REMATCH[2]} * 10))
    fi
    local now_ms
    if [[ -n $EPOCHREALTIME ]]; then
        now_ms=${EPOCHREALTIME//[!0-9]/}
        now_ms=$((10#$now_ms / 1000))
    else
        now_ms=$(date +%s)000
    fi

    # The TUIs: pid, start, cwd, and what codex.jq needs to pair them. A cwd
    # with a line break in it cannot travel on one line, and is left out.
    local pid cwd stream='' line escaped
    local -A tui_cwds=() is_tui=() resume_ids=()
    for pid in "${tuis[@]}"; do
        __as_start_ticks "$pid" || continue
        cwd=${__as_resolved[$__as_proc/$pid/cwd]}
        [[ -n $cwd && $cwd != *$'\n'* ]] || continue
        __as_ticks_ms "$__as_ticks"
        __as_git "$cwd"
        printf -v line '\x1dP\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' \
            "$pid" "$__as_ticks" "$__as_ms" "$cwd" "${__as_codex_resume[pid]}" \
            "${__as_codex_picker[pid]}" "$__as_repo" "$__as_branch"
        stream+=$line
        is_tui[$pid]=1
        # The cwd as a rollout's first line spells it, JSON-escaped, so threads
        # in a directory no TUI is in are never read past that line.
        escaped=${cwd//\\/\\\\}
        escaped=${escaped//\"/\\\"}
        tui_cwds[$escaped]=1
        [[ -n ${__as_codex_resume[pid]} ]] && resume_ids[${__as_codex_resume[pid]}]=1
    done
    ((${#is_tui[@]} > 0)) || return 0

    # Every rollout a TUI or a holder has open that could be a TUI's thread:
    # written by the TUI (`"originator":"codex-tui"`), not a subagent's, and in
    # a directory some TUI is in - or held by a TUI itself, or named by one.
    local f path first home id thread_cwd
    local -a files=() file_holders=() file_homes=() file_firsts=() thread_ids=()
    local -A seen_files=() homes=()
    local re_rollout='^(.*)/sessions/[0-9]{4}/[0-9]{2}/[0-9]{2}/rollout-[0-9T:-]+-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(_[^/]*)?\.jsonl$'
    local re_cwd='"cwd":"((\\.|[^"\\])*)"'
    for pid in "${tuis[@]}" "${holders[@]}"; do
        for f in "$__as_proc/$pid/fd/"*; do
            path=${__as_resolved[$f]}
            [[ $path == */rollout-*.jsonl && $path =~ $re_rollout ]] || continue
            home=${BASH_REMATCH[1]}
            id=${BASH_REMATCH[2]}
            [[ -z ${seen_files[$path]} && -f $path ]] || continue
            seen_files[$path]=1
            first=
            IFS= read -r -n 4096 first 2>/dev/null <"$path"
            [[ $first == *'"originator":"codex-tui"'* ]] || continue
            [[ $first == *'"thread_source":"subagent"'* || $first == *'"parent_thread_id":"'* ]] && continue
            if [[ -z ${is_tui[$pid]} && -z ${resume_ids[$id]} ]]; then
                thread_cwd=
                [[ $first =~ $re_cwd ]] && thread_cwd=${BASH_REMATCH[1]}
                [[ -n ${tui_cwds[$thread_cwd]} ]] || continue
            fi
            files+=("$path")
            file_holders+=("$pid")
            file_homes+=("$home")
            file_firsts+=("$first")
            thread_ids+=("$id")
            homes[$home]=1
            ((${#files[@]} < 32)) || break 2
        done
    done
    ((${#files[@]} > 0)) || return 0

    # Thread names, from each home's session index: append-only, newest last,
    # one grep per home for every thread in it.
    local -a patterns=()
    for home in "${!homes[@]}"; do
        [[ -f $home/session_index.jsonl ]] || continue
        patterns=()
        for id in "${thread_ids[@]}"; do
            patterns+=(-e "\"id\":\"$id\"")
        done
        while IFS= read -r line; do
            stream+=$'\x1dI\x1f'"$line"$'\n'
        done < <(grep -h -F "${patterns[@]}" -- "$home/session_index.jsonl" 2>/dev/null | head -c 1048576)
    done

    # The children of each process that holds a thread, once per process.
    local -A children=()
    for pid in "${file_holders[@]}"; do
        [[ -n ${children[$pid]+set} ]] && continue
        __as_codex_children_of "$pid" "$uptime_ms"
        children[$pid]=$__as_codex_children
    done

    local -a records=()
    local out i
    out=$(
        {
            printf '%s' "$stream"
            for i in "${!files[@]}"; do
                printf '\x1e\n\x1dT\x1f%s\x1f%s\x1f%s\n' "${file_holders[i]}" "${files[i]}" "${file_homes[i]}"
                printf '\x1dM\x1f%s\n' "${file_firsts[i]//[$'\x1d\x1e\x1f']/}"
                printf '%s' "${children[${file_holders[i]}]}"
                tail -c 131072 -- "${files[i]}" 2>/dev/null
                echo
            done
        } | jq -ncR -f "$__as_lib/codex.jq" --argjson now "$now_ms" \
            --arg home "$HOME/.codex" 2>/dev/null
    ) || return 0

    # Every line jq printed is a whole record, since it exited cleanly; it pairs
    # TUIs with threads itself, so there is no count to check against.
    [[ -n $out ]] || return 0
    mapfile -t records <<<"$out"
    __as_records+=("${records[@]}")
}
