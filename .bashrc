set -o vi

if [ -d "$HOME/bin" ]; then export PATH="$HOME/bin:$PATH"; fi
VIM=`which vim`; if [ -f "$VIM" ]; then export EDITOR="$VIM"; fi

case "$OSTYPE" in
  freebsd*)
    alias ls='ls -G'
    ;;
  linux-gnu)
    alias ls='ls --color=auto'

    if ! shopt -oq posix; then
      if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
      elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
      fi
    fi

    ;;
esac

alias grep='grep --color=auto'
