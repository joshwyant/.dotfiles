#!/bin/bash

# Personal info
GH_USERID="joshwyant"
GH_EMAIL="1755797+joshwyant@users.noreply.github.com"
GIT_NAME="Josh W"
KEY_FILE=$HOME/Downloads/"Josh W (F31AE17F) – Secret.asc"
TRUST_FILE=$HOME/Downloads/otrust.lst

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${BASEDIR}"

# Install package sources
add_package_source() {
  keyurl=$1
  pkg_src=$2
  pkg_target=$3
  pkg_release=$4
  keyfile=$5
  listfile=$6
  if [[ ! -f /etc/apt/keyrings/$keyfile ]]; then
    sudo curl -fsSLo /etc/apt/keyrings/$keyfile $keyurl
  fi
  if [[ ! -f $listfile ]]; then
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/$keyfile] $pkg_src $pkg_target $pkg_release" | sudo tee /etc/apt/sources.list.d/$listfile > /dev/null 
  fi
}

# Docker
add_package_source \
  https://download.docker.com/linux/ubuntu/gpg \
  https://download.docker.com/linux/ubuntu $(lsb_release -sc) stable \
  docker.asc \
  docker.list

# Gramine
add_package_source \
  https://packages.gramineproject.io/gramine-keyring-$(lsb_release -sc).gpg \
  https://packages.gramineproject.io $(lsb_release -sc) main \
  gramine-keyring-$(lsb_release -sc).gpg \
  gramine.list

# Intel SGX
add_package_source \
  https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key \
  https://download.01.org/intel-sgx/sgx_repo/ubuntu $(lsb_release -sc) main \
  intel-sgx-deb.asc \
  intel-sgx.list

# Don't install these on WSL
if ! uname -r | grep -qi "microsoft"; then
  # VSCode
  add_package_source \
    https://packages.microsoft.com/keys/microsoft.asc \
    https://packages.microsoft.com/repos/code stable main \
    packages.microsoft.asc \
    vscode.list

  # Brave Browser
  add_package_source \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/ stable main \
    brave-browser-archive-keyring.gpg \
    brave-browser-release.list
fi

# Apply new package lists, and update software
sudo apt update && sudo apt upgrade -y

# Figure out python version
if [[ $(lsb_release -sc) == "noble" ]]; then
  # Ubuntu 24.04
  PYTHON_VER=python3.12
elif [[ $(lsb_release -sc) == "jammy" ]]; then
  # Ubuntu 22.04
  PYTHON_VER=python3.10
else
  echo "Unsupported release $(lsb_release -sc)!"
  exit
fi

# Install software
sudo apt install -y \
  git build-essential tmux vim \
  $PYTHON_VER-venv \
  cpuid \
  openssh-server \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  libsgx-quote-ex libsgx-dcap-ql \
  libsgx-dcap-quote-verify-dev libsgx-dcap-default-qpl-dev \
  gramine \
  pkg-config libssl-dev protobuf-compiler

# Additional GUI applications if not WSL
if uname -r | grep -qi "microsoft"; then
  echo "Running under WSL"
else
  sudo apt install -y \
    code brave-browser
fi

# Configure docker
sudo usermod -aG docker $USER

# Configure SSH
if [[ ! -f $HOME/.ssh/id_ed25519 ]]; then
  ssh-keygen -t ed25519 -q -f "$HOME/.ssh/id_ed25519" -N "" -C "${GH_EMAIL}"
  eval "$(ssh-agent -s)"
  ssh-import-id-gh $GH_USERID
  cat ~/.ssh/id_ed25519.pub
  read -n 1 -p "Save the SSH public key in GitHub and in remote authorized_keys files, and press any key to continue"
fi

# Configure git
git config --global user.email "${GH_EMAIL}"
git config --global user.name "${GIT_NAME}"

# Configure GPG & git signing
export KEY_FILE && export TRUST_FILE && \
  ./import-gpg-key.sh

# Install rust
if [[ -z $(which rustc) ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s --   -y --default-toolchain nightly
  source "$HOME/.cargo/env"
else
  echo Rust is already installed.
fi

# Configure SGX
sudo usermod -aG sgx $USER
sudo sed -s -i 's/localhost:8081/api.trustedservices.intel.com/' /etc/sgx_default_qcnl.conf
if [[ ! -f $HOME/.config/gramine/enclave-key.pem ]]; then
  gramine-sgx-gen-private-key
fi

# Install Fortanix EDP
if [[ -z $(which sgx-detect) ]]; then
  rustup target add x86_64-fortanix-unknown-sgx --toolchain nightly
  cargo install fortanix-sgx-tools sgxs-tools
  # sgx-detect
else
  echo Fortanix EDP is already installed.
fi

# Set up source repos
mkdir -p $HOME/src

read -r -p "Do you want to reboot now? [y/N] " yesno
if [[ ${yesno,,} =~ ^(y|yes)$ ]]; then
    sudo reboot
fi

sync() {
  # Link dotfiles
  if [[ ! -f ~/.vimrc ]]; then
    ln -s ./.vimrc ~/.vimrc
  fi
}

# Link dotfiles
if [[ ! -f ~/.vimrc ]]; then
  ln -s $(readlink -f ../.vimrc) ~/.vimrc
fi
if [[ ! -f ~/.tmux.conf ]]; then
  ln -s $(readlink -f ../.tmux.conf) ~/.tmux.conf
fi

mkdir -p ~/.gnupg
if [[ ! -f ~/.gnupg/gpg.conf ]]; then
  ln -s $(readlink -f ../.gnupg/gpg.conf) ~/.gnupg/gpg.conf
fi
if [[ ! -f ~/.gnupg/gpg-agent.conf ]]; then
  ln -s $(readlink -f ../.gnupg/gpg-agent.conf) ~/.gnupg/gpg-agent.conf
fi