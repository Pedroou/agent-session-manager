# shellcheck shell=bash
# shellcheck disable=SC2154 # $__as_proc, $__as_lib and every answer common.bash
# hands back are set outside this file: by agent-sessions, which sources it.
# OMP's (oh-my-pi's) sessions, for agent-sessions.
#
# OMP writes no registry of live sessions, but every running session is a
# process, and that process holds its transcript open for as long as it writes
# to it. So the process table says which sessions are alive, its fd table says
# which transcript each one is, and the tail of that transcript says what it is
# doing (omp.jq) - all three from files.
#
# Its cost has a ceiling whatever the machine is doing: at most 32 sessions, and
# per session one `tail` of at most 128 KiB plus a first line of at most 4 KiB -
# so the one jq they share never sees more than about 4 MiB. A command that
# cannot start, for want of memory or processes or anything else, costs the OMP
# rows of that one refresh and nothing more: nothing is retried, nothing is
# written, and every other agent's rows still print.

# Every OMP session process, in ascending pid order, into __as_omp_pid_list. The
# compiled binary runs as `omp`; an install run through bun or node shows that
# runtime's name with omp's script as the first argument. OMP's own helper
# processes (`omp __omp_worker_…`) share the name, and are dropped - none of
# them is a session.
#
# Every read has a ceiling (`read -n`), so no file - a process's argv, a
# breadcrumb, a transcript with no newline in it - can make this hold more than
# a few kilobytes of it in memory. And every read has its errors discarded: a
# process can exit between the glob and the read.
#
# This walks every process on the machine, so it sticks to glob tests: a bash
# regex is compiled afresh each time it is matched.
__as_omp_pids() {
    local entry pid comm a0 a1 a2
    local -a by_pid=()
    __as_omp_pid_list=()
    # Indexing a sparse array by pid sorts them numerically for free.
    for entry in "$__as_proc"/[1-9]*; do
        pid=${entry##*/}
        [[ $pid == *[!0-9]* ]] || by_pid[pid]=1
    done
    for pid in "${!by_pid[@]}"; do
        comm=
        IFS= read -r -n 64 comm 2>/dev/null <"$__as_proc/$pid/comm"
        case $comm in
        omp | bun | node) ;;
        *) continue ;;
        esac
        # The first three arguments are all that is looked at: the helper's
        # marker comes first for the binary, second through bun or node.
        a0='' a1='' a2=''
        [[ -r $__as_proc/$pid/cmdline ]] || continue
        {
            IFS= read -r -d '' -n 4096 a0
            IFS= read -r -d '' -n 4096 a1
            IFS= read -r -d '' -n 4096 a2
        } 2>/dev/null <"$__as_proc/$pid/cmdline"
        [[ -n $a0 ]] || continue
        [[ $a1 == __omp_* || $a2 == __omp_* ]] && continue
        if [[ $comm != omp ]]; then
            [[ $a1 =~ (^|/)omp$|/pi-coding-agent/ ]] || continue
        fi
        __as_omp_pid_list+=("$pid")
    done
}

# Only a file named the way OMP names a session's transcript is ever read as
# one: <timestamp>_<session-id>.jsonl, and a regular file at that.
__as_omp_is_transcript() {
    [[ $1 == */*.jsonl && $1 =~ /[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9-]+Z_[^/]+\.jsonl$ ]]
}

# The transcript an OMP process belongs to, as a path in __as_transcript - which
# may not exist yet, for a session nobody has typed into. Also sets __as_cwd to
# the process's working directory. Both come out of __as_resolved.
#
# First choice is the one it has open. A session's transcript is named
# <timestamp>_<session-id>.jsonl; a subagent's, which the same process also
# holds open, is named after the agent - so the name alone tells them apart.
#
# A session OMP has not written yet holds nothing open, and nor does one that
# was resumed and has not written since. For those there is the breadcrumb OMP
# leaves per terminal, which is how its own `--continue` knows what was last
# open there: <agent-dir>/terminal-sessions/<tty>, holding the cwd and the
# transcript path. It is trusted only when its cwd is the process's own, since a
# terminal outlives the sessions run in it.
__as_omp_transcript() {
    local pid=$1
    __as_transcript=
    __as_cwd=${__as_resolved[$__as_proc/$pid/cwd]}

    # In fd order, numerically, which a plain glob would not give.
    local f fd
    local -a by_fd=() others=() candidates=()
    for f in "$__as_proc/$pid/fd/"*; do
        fd=${f##*/}
        if [[ $fd == 0 || ($fd == [1-9]* && $fd != *[!0-9]*) ]]; then
            by_fd[fd]=$f
        else
            others+=("$f")
        fi
    done
    for f in "${by_fd[@]}" "${others[@]}"; do
        f=${__as_resolved[$f]}
        __as_omp_is_transcript "$f" && [[ -f $f ]] && candidates+=("$f")
    done
    if ((${#candidates[@]} > 0)); then
        __as_newest_of "${candidates[@]}"
        __as_transcript=$__as_newest
        [[ -n $__as_transcript ]] && return 0
    fi

    # OMP names a terminal after its tty, /dev/pts/4 becoming pts-4. Only
    # `readlink` itself here: `realpath` would chase a link it cannot follow.
    local tty
    tty=$(readlink -- "$__as_proc/$pid/fd/0" 2>/dev/null)
    [[ $tty =~ ^/dev/. ]] || return 1
    local terminal=${tty:5}
    terminal=${terminal//\//-}
    local crumb crumb_cwd crumb_file
    local -a crumbs=() crumb_files=()
    for crumb in "$HOME/.omp/agent/terminal-sessions/$terminal" \
        "$HOME"/.omp/profiles/*/agent/terminal-sessions/"$terminal"; do
        [[ -f $crumb ]] || continue
        crumb_cwd='' crumb_file=''
        {
            IFS= read -r -n 4096 crumb_cwd
            IFS= read -r -n 4096 crumb_file
        } 2>/dev/null <"$crumb"
        [[ $crumb_cwd == "$__as_cwd" ]] || continue
        __as_omp_is_transcript "$crumb_file" || continue
        crumbs+=("$crumb")
        crumb_files+=("$crumb_file")
    done
    ((${#crumbs[@]} > 0)) || return 1
    __as_newest_of "${crumbs[@]}"
    local i
    for i in "${!crumbs[@]}"; do
        if [[ ${crumbs[i]} == "$__as_newest" ]]; then
            __as_transcript=${crumb_files[i]}
            break
        fi
    done
    [[ -n $__as_transcript ]]
}

__as_omp_collect() {
    __as_omp_pids
    local -a pids=("${__as_omp_pid_list[@]:0:32}")
    ((${#pids[@]} > 0)) || return 0

    local btime='' line
    __as_resolve_all "${pids[@]}"
    if [[ -r $__as_proc/stat ]]; then
        while IFS= read -r line; do
            if [[ $line == 'btime '* && $line =~ ^btime\ ([0-9]+)$ ]]; then
                btime=${BASH_REMATCH[1]}
                break
            fi
        done 2>/dev/null <"$__as_proc/stat"
    fi

    local -a files=() meta=() records=()
    local pid ticks cwd file session_id file_dir sessions_dir agent_dir
    local label omp_profile is_default started
    for pid in "${pids[@]}"; do
        # Gone since the scan: nothing to report, and nothing to end later.
        __as_start_ticks "$pid" || continue
        ticks=$__as_ticks
        __as_omp_transcript "$pid" || continue
        cwd=$__as_cwd
        file=$__as_transcript
        session_id=
        [[ $file =~ _([^_/]+)\.jsonl$ ]] && session_id=${BASH_REMATCH[1]}

        # Transcripts live at <agent-dir>/sessions/<project>/<file>, unless
        # --session-dir put them somewhere else - in which case the directory
        # holding the file is all there is to say about where it came from.
        __as_dirname "$file"
        file_dir=$__as_dir
        __as_dirname "$file_dir"
        sessions_dir=$__as_dir
        __as_dirname "$sessions_dir"
        agent_dir=$__as_dir
        __as_basename "$sessions_dir"
        [[ $__as_base == sessions ]] || agent_dir=$file_dir

        # The stock agent directory resumes with a plain `omp --resume`, and a
        # named profile (`omp --profile <name>`) lives under ~/.omp/profiles.
        label=OMP
        omp_profile=
        is_default=false
        if [[ $agent_dir == "$HOME/.omp/agent" ]]; then
            is_default=true
        elif [[ $agent_dir == "$HOME/.omp/profiles/"* &&
            ${agent_dir#"$HOME/.omp/profiles/"} =~ ^([^/]+)/agent$ ]]; then
            omp_profile=${BASH_REMATCH[1]}
            label="OMP $omp_profile"
        fi

        # Epoch milliseconds: /proc/stat has the boot time, and USER_HZ is 100
        # on every architecture Linux exposes to userspace, so a tick is 10 ms.
        started=0
        [[ -n $btime ]] && started=$(((btime * 100 + ticks) * 10))

        __as_git "$cwd"

        files+=("$file")
        # Each with the ":" that keeps jq from reading a leading "-" as an option.
        meta+=(":$pid" ":$session_id" ":$cwd" ":$started" ":$file"
            ":$omp_profile" ":$ticks" ":$label" ":$agent_dir" ":$is_default"
            ":$__as_repo" ":$__as_branch")
    done

    ((${#files[@]} > 0)) || return 0

    # One stream for every session, read by omp.jq: a record separator opens
    # each, then the transcript's first line - the title, kept in a fixed-width
    # slot OMP rewrites in place - then its tail. A separator cannot occur inside
    # JSON text, so it is never mistaken for a line of transcript.
    local f first
    mapfile -t records < <(
        for f in "${files[@]}"; do
            printf '\x1e\n'
            [[ -f $f ]] || continue
            first=
            IFS= read -r -n 4096 first 2>/dev/null <"$f"
            printf '%s\n' "$first"
            tail -c 131072 -- "$f" 2>/dev/null
            echo
        done | jq -ncR -f "$__as_lib/omp.jq" --args "${meta[@]}" 2>/dev/null)

    # One record per session or none at all: a jq that fell over halfway must
    # not leave the panel with some sessions and not others.
    if ((${#records[@]} == ${#files[@]})); then
        __as_records+=("${records[@]}")
    fi
}
