# shellcheck shell=bash
# shellcheck disable=SC2154 # $__as_proc, $__as_lib and every answer common.bash
# hands back are set outside this file: by agent-sessions, which sources it.
# Claude Code's sessions, for agent-sessions.
#
# Claude Code keeps a registry of its own live sessions at
# <profile-dir>/sessions/<pid>.json, refreshed as the session changes state. The
# fields read here are `status` (one of busy/shell/idle/waiting), `waitingFor`,
# `needs`, `name`, `cwd` and `procStart`. Records are left behind when a session
# is killed rather than exiting cleanly, so every record is checked against /proc
# before it is reported: the process must still exist *and* its start time must
# match, which is what rules out a recycled pid.
#
# Two of the reported states are not in the registry at all and are worked out
# here (see __as_claude_running and __as_claude_error below):
#
#   running  a shell command or script is executing inside a busy session
#   error    an idle session whose last turn ended in an API error
#
# Record bodies and git metadata are read with bash builtins. Only idle sessions
# pay for a transcript read, and only busy ones for a /proc walk; each session
# with a transcript then costs one `tac` for its model, and all of them share
# one jq (claude.jq).
#
# Environment:
#   CLAUDE_PROFILES          JSON array of {name, dir} to read, in order
#   AGENT_SESSIONS_NO_ERROR  set to skip the transcript scan for errors entirely

# Is a command running inside this session?
#
# Claude Code runs every Bash tool call as a direct child shell of its own
# process, so a child whose comm is a shell means "a command or script is
# executing". Its long-lived children are MCP servers (`npm exec …`, `node`),
# which are not shells, so the two never get confused. Subagents run inside the
# process and leave no trace here - they stay indistinguishable from thinking.
#
# Sets __as_command to the command being run, when it can be recovered, and
# returns 1 when nothing is running.
__as_claude_running() {
    local pid=$1
    __as_command=
    # The main thread is where Claude Code's forks are attributed, and reading one
    # file beats globbing the dozens of task/ entries a node process has.
    local children_file=$__as_proc/$pid/task/$pid/children
    [[ -r $children_file ]] || return 1
    local -a kids=()
    read -r -a kids 2>/dev/null <"$children_file"
    ((${#kids[@]} > 0)) || return 1

    local kid comm part found shown
    local quote_dance="'\"'\"'" eval_tail="^(.*)' *<[^<]*\$"
    for kid in "${kids[@]}"; do
        comm=
        read -r -n 64 comm 2>/dev/null <"$__as_proc/$kid/comm"
        case $comm in
        bash | sh | dash | zsh | fish | ksh) ;;
        *) continue ;;
        esac

        # Claude Code wraps each command as `… && eval '<command>' < /dev/null …`
        # after sourcing a shell snapshot. The eval'd text is the part worth
        # showing, taken up to the end of its first line. argv is NUL-separated,
        # and no one argument can be longer than the kernel's 128 KiB limit.
        shown=
        if [[ -r $__as_proc/$kid/cmdline ]]; then
            while IFS= read -r -d '' -n 131072 part || [[ -n $part ]]; do
                [[ $part == *"eval '"* ]] || continue
                found=${part#*"eval '"}
                found=${found%%$'\n'*}
                [[ -n $found ]] || continue
                shown=$found
                [[ $shown =~ $eval_tail ]] && shown=${BASH_REMATCH[1]}
                # The command was single-quoted for eval, so its own quotes arrive
                # as the '"'"' dance. Undo that, then flatten it onto one line.
                shown=${shown//"$quote_dance"/"'"}
                shown=${shown//[$'\t\v\f\r']/ }
                __as_split "$shown"
                shown="${__as_words[*]}"
                break
            done 2>/dev/null <"$__as_proc/$kid/cmdline"
        fi
        __as_command=${shown:0:120}
        return 0
    done
    return 1
}

# A Claude Code session's transcript: <profile>/projects/<project>/<id>.jsonl.
# Sets __as_claude_transcript, empty when there is none yet.
__as_claude_transcript_of() {
    local profile_dir=$1 session_id=$2 t
    __as_claude_transcript=
    [[ -n $session_id ]] || return
    for t in "$profile_dir"/projects/*/"$session_id".jsonl; do
        if [[ -f $t ]]; then
            __as_claude_transcript=$t
            return
        fi
    done
}

# Did this session's last turn end in an API error?
#
# The registry has no error state - a session that fails goes back to `idle` -
# but the transcript records it, and unlike a live status the transcript is
# reliable here precisely because the session has stopped writing. The last
# assistant entry carries `isApiErrorMessage` and a message worth showing
# ("You've hit your session limit · resets 6:40pm", "Login expired · Please run
# /login"). Reading only the tail keeps the cost off the size of the file.
#
# Sets __as_message to the message, and returns 1 when the last turn was fine.
__as_claude_error() {
    local transcript=$1
    __as_message=
    [[ -n $transcript ]] || return 1
    [[ -z $AGENT_SESSIONS_NO_ERROR ]] || return 1

    local tail_text
    tail_text=$(tail -c 32768 -- "$transcript" 2>/dev/null)
    [[ $tail_text == *'"isApiErrorMessage":true'* ]] || return 1

    # `fromjson?` drops the partial first line a byte-offset tail leaves behind.
    # -s matters: without it jq runs the filter per line, and "the last assistant
    # entry" silently becomes "any line that is an error".
    local message
    message=$(printf '%s' "$tail_text" | jq -Rsr '
        [splits("\n") | fromjson? ]
        | map(select(.type == "assistant"))
        | last
        | select(.isApiErrorMessage == true)
        | (.message.content[0]?.text // "")
        | .[0:200]' 2>/dev/null)
    # Trimmed, and on one line.
    message=${message#"${message%%[![:space:]]*}"}
    message=${message%"${message##*[![:space:]]}"}

    [[ -n $message ]] || return 1
    __as_message=${message//$'\n'/ }
}

__as_claude_collect() {
    # Which config directories to read, and what to call each one.
    #
    # Claude Code's own mechanism for a second account is $CLAUDE_CONFIG_DIR,
    # which takes any path at all - so there is no set of directories to
    # hardcode, and the widget hands over the list the user configured. Derived
    # per run, never cached at load time: the test suite moves $HOME.
    local -a names=() dirs=() flat=()
    local i dir id
    if [[ -n $CLAUDE_PROFILES ]]; then
        # One jq, two lines per profile. Reading names and directories in separate
        # calls would double the only fork this parsing costs.
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
    # Only when nothing was handed over at all. An empty list is an answer - every
    # account turned off, or the last one removed - and answering it with a
    # directory nobody asked for is how "no accounts" became unreachable.
    if ((${#dirs[@]} == 0)) && [[ -z $CLAUDE_PROFILES ]]; then
        names=(default)
        dirs=("$HOME/.claude")
    fi

    local -a bodies=() transcripts=() meta=() records=() by_pid=()
    local record pid body want_start status_now session_id cwd overlay detail is_default
    local re_proc_start='"procStart"[[:space:]]*:[[:space:]]*"([^"]*)"'
    local re_status='"status"[[:space:]]*:[[:space:]]*"([^"]*)"'
    local re_session_id='"sessionId"[[:space:]]*:[[:space:]]*"([^"]*)"'
    local re_cwd='"cwd"[[:space:]]*:[[:space:]]*"([^"]*)"'

    for i in "${!dirs[@]}"; do
        id=${names[i]}
        dir=${dirs[i]}
        # The stock directory is the one place $CLAUDE_CONFIG_DIR must never be
        # set to, so a session from it gets a plain `claude --resume`.
        is_default=false
        [[ $dir == "$HOME/.claude" ]] && is_default=true
        [[ -d $dir ]] && __as_profiles+=("$id")

        # Records in pid order, numerically. A name with a leading zero is never
        # a live pid, since /proc has none.
        by_pid=()
        for record in "$dir"/sessions/*.json; do
            pid=${record##*/}
            pid=${pid%.json}
            [[ $pid =~ ^[1-9][0-9]*$ ]] && by_pid[pid]=$record
        done

        for pid in "${!by_pid[@]}"; do
            record=${by_pid[pid]}
            [[ -f $record ]] || continue

            # A torn record - Claude Code rewriting the file while this reads it -
            # is not valid JSON. Requiring a complete object drops just that one
            # record and keeps the rest of the panel, and claude.jq drops one that
            # only looked complete. Trimmed, with any line breaks turned into
            # spaces, which JSON allows - so the body is one line of claude.jq's
            # input.
            body=
            IFS= read -r -d '' body 2>/dev/null <"$record"
            body=${body#"${body%%[![:space:]]*}"}
            body=${body%"${body##*[![:space:]]}"}
            body=${body//$'\n'/ }
            [[ $body == \{*\} ]] || continue

            want_start=
            [[ $body =~ $re_proc_start ]] && want_start=${BASH_REMATCH[1]}
            __as_alive "$pid" "$want_start" || continue

            status_now='' session_id='' cwd=''
            [[ $body =~ $re_status ]] && status_now=${BASH_REMATCH[1]}
            [[ $body =~ $re_session_id ]] && session_id=${BASH_REMATCH[1]}
            [[ $body =~ $re_cwd ]] && cwd=${BASH_REMATCH[1]}

            __as_claude_transcript_of "$dir" "$session_id"

            # Only busy sessions can be running a command, and only idle ones can
            # be sitting on a failed turn - so neither check runs where it can't
            # apply.
            overlay=
            detail=
            if [[ $status_now == busy ]]; then
                if __as_claude_running "$pid"; then
                    overlay=running
                    detail=$__as_command
                fi
            elif [[ $status_now == idle ]]; then
                if __as_claude_error "$__as_claude_transcript"; then
                    overlay=error
                    detail=$__as_message
                fi
            fi

            __as_git "$cwd"

            bodies+=("$body")
            transcripts+=("$__as_claude_transcript")
            # Every value carries a leading ":" because jq still reads an argument
            # beginning with "-" as an option, even after --args - and a command
            # line or an error message can quite reasonably start with one. jq
            # strips it.
            meta+=(":$id" ":$overlay" ":$detail" ":$__as_repo" ":$__as_branch"
                ":$dir" ":$is_default")
        done
    done

    ((${#bodies[@]} > 0)) || return 0

    # One stream for every session, read by claude.jq: a record separator opens
    # each, then its registry record, then the newest assistant lines of its
    # transcript, which carry the model id and the request's token counts. `tac`
    # reads a transcript from its end and grep stops at the fourth assistant
    # line, so the cost does not grow with the length of the conversation. A
    # separator cannot occur inside JSON text, so it is never mistaken for a line.
    local t
    mapfile -t records < <(
        for i in "${!bodies[@]}"; do
            printf '\x1e\n%s\n' "${bodies[i]}"
            t=${transcripts[i]}
            [[ -n $t ]] || continue
            tac -- "$t" 2>/dev/null | grep -a -m 4 -F '"type":"assistant"'
        done | jq -ncR -f "$__as_lib/claude.jq" --args "${meta[@]}" 2>/dev/null)

    # One line per session or none at all: a jq that fell over halfway must not
    # leave the panel with some sessions and not others.
    if ((${#records[@]} == ${#bodies[@]})); then
        __as_records+=("${records[@]}")
    fi
}
