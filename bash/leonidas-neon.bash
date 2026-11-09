# Leonidas - Neon Light : Git Bash setup (eza + starship)
# Sourced from ~/.bashrc by install.ps1:
#   [ -f ~/.config/leonidas-neon-light/leonidas-neon.bash ] && . ~/.config/leonidas-neon-light/leonidas-neon.bash

# Tools installed with winget are not always on the Git Bash PATH:
# add their package folders (glob = survives version upgrades).
for _lnl_dir in "$LOCALAPPDATA"/Microsoft/WinGet/Packages/eza-community.eza_* \
                "$LOCALAPPDATA"/Microsoft/WinGet/Packages/Starship.Starship_*; do
    [[ -d "$_lnl_dir" ]] && case ":$PATH:" in
        *":$_lnl_dir:"*) ;;
        *) PATH="$_lnl_dir:$PATH" ;;
    esac
done
unset _lnl_dir

# --- eza : ls with icons, directories first, git status in long views ---
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons=auto --group-directories-first'
    alias ll='eza -l --icons=auto --group-directories-first --git'
    alias la='eza -la --icons=auto --group-directories-first --git'
    alias lt='eza --tree --level=2 --icons=auto --group-directories-first'
fi

# --- starship : neon powerline prompt ---
if command -v starship >/dev/null 2>&1 && [[ -z "$STARSHIP_SHELL" ]]; then
    eval "$(starship init bash)"
fi
