# shellcheck shell=bash
# shellcheck disable=SC2154 # $__as_proc is set by agent-sessions, which sources this.
# Helpers every agent's collector shares, sourced by agent-sessions before any
# of them. None of them knows about a particular agent.
#
# They hand their answers back in global variables rather than on stdout:
# capturing a function's output with $(...) would fork a subshell for every
# session on every poll.

# A path with its last component taken off, the way `dirname` does it - without
# the fork. Sets __as_dir.
__as_dirname() {
    local p=$1
    while [[ $p == */ && $p != / ]]; do p=${p%/}; done
    if [[ $p != */* ]]; then
        __as_dir=.
        return
    fi
    p=${p%/*}
    while [[ $p == */ ]]; do p=${p%/}; done
    [[ -n $p ]] || p=/
    __as_dir=$p
}

# A path's last component, the way `basename` does it. Sets __as_base.
__as_basename() {
    local p=$1
    while [[ $p == */ && $p != / ]]; do p=${p%/}; done
    [[ $p == / ]] || p=${p##*/}
    __as_base=$p
}

# A string's words, split on blanks, into __as_words. Globbing is held off while
# it splits, so a word like `*` stays a word.
__as_split() {
    local IFS=$' \t\n'
    set -f
    # shellcheck disable=SC2206 # splitting is the point
    __as_words=($1)
    set +f
}

# Field 22 of a /proc/<pid>/stat line: the process start time in clock ticks,
# which is exactly what Claude Code stores as `procStart`. Field 2 is the
# executable name in parentheses and may itself contain spaces or parens, so the
# fields are counted from after the *last* ')' - where field 22 overall becomes
# field 20. Sets __as_field (empty when there is no such field).
__as_stat_start() {
    __as_split "${1##*)}"
    __as_field=${__as_words[19]}
}

# Is `pid` still the same process that started at `want_start` ticks?
__as_alive() {
    local pid=$1 want_start=$2
    local statfile=$__as_proc/$pid/stat line=
    [[ -r $statfile ]] || return 1
    IFS= read -r -n 4096 line 2>/dev/null <"$statfile"
    [[ -n $line ]] || return 1
    if [[ -z $want_start ]]; then
        return 0 # older record with no start time recorded: existence is all we have
    fi
    __as_stat_start "$line"
    [[ -n $__as_field && $__as_field == "$want_start" ]]
}

# When a process started, in clock ticks since boot: field 22 of its stat (see
# __as_stat_start). Sets __as_ticks, and returns 1 when the process is gone.
__as_start_ticks() {
    local pid=$1 line=
    __as_ticks=
    [[ -r $__as_proc/$pid/stat ]] || return 1
    IFS= read -r -n 4096 line 2>/dev/null <"$__as_proc/$pid/stat"
    __as_stat_start "$line"
    [[ $__as_field =~ ^[0-9]+$ ]] || return 1
    __as_ticks=$__as_field
}

# The git repository a session is sitting in, as "name" and "branch".
#
# Walks up for a .git rather than shelling out to git, which would be two more
# processes per session on every poll. Sets __as_repo and __as_branch (either
# may be empty).
__as_git() {
    local root='' probe=$1 i line
    __as_repo=
    __as_branch=
    # Bounded so a pathological path can't spin, and absolute paths are shallow.
    for ((i = 0; i < 40; i++)); do
        [[ -n $probe ]] || break
        if [[ -e $probe/.git ]]; then
            root=$probe
            break
        fi
        __as_dirname "$probe"
        [[ $__as_dir == "$probe" ]] && break
        probe=$__as_dir
    done

    [[ -n $root ]] || return 0

    # A worktree or submodule has .git as a file pointing at the real directory.
    local gitdir=$root/.git
    if [[ -f $gitdir ]]; then
        local pointer='' pointer_re='^gitdir:[[:space:]]*(.*)$'
        while IFS= read -r -n 4096 line || [[ -n $line ]]; do
            if [[ $line =~ $pointer_re ]]; then
                pointer=${BASH_REMATCH[1]}
                pointer=${pointer%"${pointer##*[![:space:]]}"}
                break
            fi
        done 2>/dev/null <"$gitdir"
        if [[ -n $pointer ]]; then
            [[ $pointer == /* ]] || pointer=$root/$pointer
            gitdir=$pointer
        fi
    fi

    if [[ -r $gitdir/HEAD ]]; then
        local head=
        read -r -n 4096 head 2>/dev/null <"$gitdir/HEAD"
        if [[ $head =~ ^ref:\ refs/heads/(.*)$ ]]; then
            __as_branch=${BASH_REMATCH[1]}
        fi
        if [[ -z $__as_branch ]]; then
            # Detached: show the short sha, which is what git itself would.
            [[ $head =~ ^[0123456789abcdef]{7,40}$ ]] && __as_branch=${head:0:7}
        fi
    fi

    __as_basename "$root"
    __as_repo=$__as_base
}

# Of these existing files, the one modified last - the first of them, on a tie.
# One `stat` for the lot, and none at all when there is only one. Sets
# __as_newest.
__as_newest_of() {
    __as_newest=$1
    (($# > 1)) || return 0
    local -a mtimes
    mapfile -t mtimes < <(stat -c %Y -- "$@" 2>/dev/null)
    local i best_mtime=0
    __as_newest=
    for ((i = 0; i < $#; i++)); do
        [[ ${mtimes[i]} =~ ^[0-9]+$ ]] || continue
        if [[ -z $__as_newest ]] || ((mtimes[i] > best_mtime)); then
            __as_newest=${*:i+1:1}
            best_mtime=${mtimes[i]}
        fi
    done
}

# Every path a process's transcript is looked for through - each process's
# working directory and open fds - resolved by one `realpath` for all of them,
# rather than one per process. -m gives one answer per path whether or not it
# leads anywhere, so they stay paired by position; should they not, each path is
# asked about on its own. Fills __as_resolved, keyed by path.
declare -A __as_resolved=()
__as_resolve_all() {
    local pid i
    local -a paths=() out=()
    for pid; do
        paths+=("$__as_proc/$pid/cwd" "$__as_proc/$pid/fd/"*)
    done
    mapfile -t -d '' out < <(realpath -m -z -- "${paths[@]}" 2>/dev/null)
    if ((${#out[@]} != ${#paths[@]})); then
        out=()
        for i in "${!paths[@]}"; do
            out[i]=$(realpath -m -- "${paths[i]}" 2>/dev/null)
        done
    fi
    for i in "${!paths[@]}"; do
        __as_resolved[${paths[i]}]=${out[i]}
    done
}
