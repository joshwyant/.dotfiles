#!/bin/bash
set -e

# TODO: Make DRY vs. Ubuntu script

# Personal info
INTERACTIVE=${INTERACTIVE:-1}
MY_USER="josh"
GH_USERID="joshwyant"
GH_EMAIL="1755797+joshwyant@users.noreply.github.com"
GIT_NAME="Josh W"
KEY_FILE=$HOME/Downloads/"Josh W (F31AE17F) – Secret.asc"
TRUST_FILE=$HOME/Downloads/otrust.lst

INSTALL_FORTANIX_EDP=1
INSTALL_RUST=1
INSTALL_PYTHON=1
ENABLE_GIT_GPG_COMMIT_SIGNING=1
ALLOW_OPENSSH_PASSWORD_AUTH=0
ALLOW_OPENSSH_PUBKEY_AUTH=1
ALWAYS_UPGRADE=0  # affects default in interactive mode, but still prompted

# Rust is required by Fortanix EDP
if [[ ($INSTALL_RUST == 1 || $INSTALL_FORTANIX_EDP == 1) && ! -f ~/.cargo/env ]]; then
  INSTALLING_RUST=1
elif [[ -f ~/.cargo/env ]]; then
  # Source it just in case for the next step.
  source ~/.cargo/env
fi

if [[ $INSTALL_FORTANIX_EDP == 1 && -z $(which sgx-detect) ]]; then
  echo "Installing fortanix."
  INSTALLING_FORTANIX_EDP=1
  RUST_CHANNEL="nightly"
fi

# Install (most) everything with homebrew
brew bundle

# Configure SSH
if [[ ! -f $HOME/.ssh/id_ed25519 ]]; then
  ssh-keygen -t ed25519 -q -f "$HOME/.ssh/id_ed25519" -N "" -C "${GH_EMAIL}"
  cat ~/.ssh/id_ed25519.pub
  if [[ $INTERACTIVE == 1 ]]; then
    read -n 1 -p "Save the SSH public key in GitHub and in remote authorized_keys files, and press any key to continue"
  fi

  eval "$(ssh-agent -s)"
fi

openssh_option() {
  # Uncomment the option
  sudo sed -s -i "s/#$1/$1/" /etc/ssh/sshd_config

  # Change from no to yes or vice-versa
  old_val="yes"
  new_val="no"
  if [[ $2 && $2 != "no" ]]; then
    old_val="no"
    new_val="yes"
  fi

  # Check if setting is incorrect, and update it
  if [[ $(cat /etc/ssh/sshd_config | grep -i "$1 $old_val" || true) ]]; then
    sudo sed -s -i "s/$1 $old_val/$1 $new_val/" /etc/ssh/sshd_config
    echo 1  # setting was changed
  else
    echo 0
  fi
}

# # Update on every run
# if [[ $INSTALL_OPENSSH_SERVER == 1 ]]; then
#   pass_auth_changed=$(openssh_option PasswordAuthentication $ALLOW_OPENSSH_PASSWORD_AUTH)
#   key_auth_changed=$(openssh_option PubkeyAuthentication $ALLOW_OPENSSH_PUBKEY_AUTH)
#   # Restart ssh server if any settings changed
#   if [[ $pass_auth_changed == 1 || $key_auth_changed == 1 ]]; then
#     sudo systemctl try-reload-or-restart ssh
#   fi
#   ssh-import-id-gh $GH_USERID 2>/dev/null
# fi

# Configure git; update on every run
git config --global user.email "${GH_EMAIL}"
git config --global user.name "${GIT_NAME}"

# # Configure GPG & git signing; update on every run
# export KEY_FILE TRUST_FILE INTERACTIVE ENABLE_GIT_GPG_COMMIT_SIGNING && \
#   ./import-gpg-key.sh

# Install rust; prerequisite for Fortanix EDP
if [[ $INSTALLING_RUST == 1 ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s --   -y --default-toolchain $RUST_CHANNEL
  source "$HOME/.cargo/env"
fi

# Install Fortanix EDP
if [[ $INSTALLING_FORTANIX_EDP == 1 ]]; then
  # Nightly toolchain is required to be the default to install Fortanix EDP
  if [[ -z $(rustup toolchain list | grep 'nightly.*default' || true) ]]; then
    rustup default nightly
  fi
  rustup target add x86_64-fortanix-unknown-sgx --toolchain nightly
  cargo install fortanix-sgx-tools sgxs-tools
  sgx-detect
fi

# Set up source repos
mkdir -p $HOME/src

sync() {
  # Link dotfiles
  if [[ ! -f $2/$1 ]]; then
    echo "Invalid filename $2/$1"
    exit 1
  fi
  if [[ ! -f $3/$1 ]]; then
    mkdir -p $3
    ln -s $(readlink -f $2/$1) $3/$1
  fi
}

# Link dotfiles
sync .vimrc .. ~
sync .tmux.conf .. ~

# Use .vimrc for .config/nvim/init.vim as well
if [[ ! -f ~/.config/nvim/init.vim ]]; then
  mkdir -p ~/.config/nvim
  ln -s $(readlink -f ../.vimrc) ~/.config/nvim/init.vim
fi

if [[ $(git status -s) ]]; then
  echo ">> There are changes to the dotfiles. Please sync them in git!"
fi

if [[ $NEED_RESTART == 1 ]]; then
  echo ">> Reboot is required."
  if [[ $INTERACTIVE == 1 ]]; then
    read -r -p "Do you want to reboot now? [y/N] " yesno
    if [[ ${yesno,,} =~ ^(y|yes)$ ]]; then
        sudo reboot
    fi
  fi
fi

if [[ $INTERACTIVE == 1 ]]; then
  echo "Finished!"
fi
