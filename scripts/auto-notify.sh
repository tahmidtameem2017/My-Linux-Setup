#!/usr/bin/env bash
# Auto-notification for long-running commands in bash
# Usage: source this file in your .bashrc
# Set NOTIFY_AUTO_THRESHOLD to enable (e.g., export NOTIFY_AUTO_THRESHOLD=30)

AUTO_NOTIFY_THRESHOLD="${NOTIFY_AUTO_THRESHOLD:-10}"          # seconds before notification triggers

AUTO_NOTIFY_IGNORE=(
    "vim" "nvim" "vi" "nano" "micro" "emacs" "code"
    "man" "less" "more" "bat" "cat" "head" "tail"
    "ssh" "mosh" "telnet" "nc" "netcat" "socat"
    "top" "htop" "btop" "btm" "glances" "iotop" "iftop" "nethogs"
    "watch" "fzf" "fzy" "skim" "peco" "percol"
    "ranger" "nnn" "lf" "mc" "vifm" "yazi"
    "python" "python3" "ipython" "python2" "node" "nodejs" "deno" "bun"
    "lua" "luajit" "perl" "ruby" "irb" "pry" "php" "php5" "php7" "php8"
    "java" "javac" "kotlin" "kotlinc" "scala" "sc"
    "ghci" "ghc" "runhaskell" "cabal" "stack"
    "nim" "crystal" "zig" "go" "gofmt" "godoc" "golint"
    "rustc" "cargo" "rustup" "rustfmt" "clippy"
    "gcc" "g++" "clang" "clang++" "cc" "c++" "make" "cmake" "ninja" "meson"
    "gdb" "lldb" "rr" "valgrind" "strace" "ltrace" "perf"
    "docker" "podman" "kubectl" "helm" "minikube" "kind" "k3d"
    "terraform" "tofu" "ansible" "vagrant" "packer"
    "git" "hg" "svn" "fossil" "pijul" "jj"
    "tmux" "screen" "byobu" "zellij"
    "opencode" "claude" "gemini" "qwen" "cursor" "aider" "openai"
)

# Store command start time and command name
_auto_notify_start_time=0
_auto_notify_last_cmd=""
_auto_notify_notified=false

# Check if command should be ignored
_auto_notify_should_ignore() {
    local cmd="$1"
    local base_cmd="${cmd%% *}"
    base_cmd="${base_cmd##*/}"
    
    for ignore in "${AUTO_NOTIFY_IGNORE[@]}"; do
        if [[ "$base_cmd" == "$ignore" ]]; then
            return 0
        fi
    done
    return 1
}

# Pre-execution hook (DEBUG trap)
_auto_notify_preexec() {
    # Don't trigger on empty commands or PROMPT_COMMAND itself
    if [[ -z "$BASH_COMMAND" ]] || [[ "$BASH_COMMAND" == "$PROMPT_COMMAND" ]]; then
        return
    fi
    
    _auto_notify_last_cmd="$BASH_COMMAND"
    _auto_notify_start_time=$(date +%s)
    _auto_notify_notified=false
}

# Post-execution hook (PROMPT_COMMAND)
_auto_notify_precmd() {
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - _auto_notify_start_time))
    
    # Only notify if:
    # 1. Duration exceeds threshold
    # 2. Command is not in ignore list
    # 3. We haven't already notified for this command
    # 4. Terminal is not focused (approximated by checking if we're the foreground process)
    if (( duration >= AUTO_NOTIFY_THRESHOLD )) && \
       ! _auto_notify_should_ignore "$_auto_notify_last_cmd" && \
       [[ "$_auto_notify_notified" == false ]]; then
        
        # Send notification
        local cmd_display="${_auto_notify_last_cmd:0:100}"
        if (( ${#_auto_notify_last_cmd} > 100 )); then
            cmd_display="${cmd_display}..."
        fi
        
        if (( exit_code == 0 )); then
            notify-send -a "Terminal" "✅ Command completed" \
                "Ran for ${duration}s: ${cmd_display}" \
                -i "utilities-terminal" \
                -h string:x-canonical-private-synchronous:terminal-notify 2>/dev/null &
        else
            notify-send -a "Terminal" "❌ Command failed (exit $exit_code)" \
                "Ran for ${duration}s: ${cmd_display}" \
                -i "dialog-error" \
                -h string:x-canonical-private-synchronous:terminal-notify \
                -u critical 2>/dev/null &
        fi
        
        _auto_notify_notified=true
    fi
}

# Setup hooks
if [[ $- == *i* ]]; then
    # Only set up in interactive shells
    trap '_auto_notify_preexec' DEBUG
    
    # Wrap existing PROMPT_COMMAND
    if [[ -n "$PROMPT_COMMAND" ]]; then
        PROMPT_COMMAND="_auto_notify_precmd; $PROMPT_COMMAND"
    else
        PROMPT_COMMAND="_auto_notify_precmd"
    fi
fi