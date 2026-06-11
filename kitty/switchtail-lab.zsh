# SwitchTail kitty cockpit launcher.
# Enable by adding this line to ~/.zshrc:
#     source ~/.config/kitty/switchtail-lab.zsh
#
#   lab              -> fzf picker over all lab cockpits
#   lab <name>       -> open that lab's cockpit (e.g. `lab agent`)
#   lab switchtail-all -> open the aggregate cockpit (one claude per lab)
# Sessions are auto-maintained by the switchtail-sessions.path systemd unit.
lab() {
  local dir="$HOME/.config/kitty/sessions/labs" sel f
  if [ -n "${1:-}" ]; then
    sel="$1"
  else
    sel="$(print -l "$dir"/*.kitty-session(N:t:r) \
           | fzf --prompt='lab cockpit > ' --height=40% --layout=reverse --no-multi)"
  fi
  [ -z "$sel" ] && return 0
  f="$dir/$sel.kitty-session"
  [ -f "$f" ] || { print -u2 "lab: no session '$sel' (try: lab  |  lab switchtail-all)"; return 1; }
  ( setsid kitty --session "$f" >/dev/null 2>&1 & )   # detached new OS window
}
_lab() { compadd -- "$HOME"/.config/kitty/sessions/labs/*.kitty-session(N:t:r); }
compdef _lab lab 2>/dev/null || true
