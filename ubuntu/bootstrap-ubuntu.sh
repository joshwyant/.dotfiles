#!/bin/bash
set -e

# Personal info
INTERACTIVE=0
MY_USER="josh"
GH_USERID="joshwyant"
GH_EMAIL="1755797+joshwyant@users.noreply.github.com"
GIT_NAME="Josh W"
KEY_FILE=$HOME/Downloads/"Josh W (F31AE17F) – Secret.asc"
TRUST_FILE=$HOME/Downloads/otrust.lst

# Main packages
EXTRA_PACKAGES=""
DEV_PACKAGES="wget curl git build-essential tmux vim protobuf-compiler"

# What else to install
INSTALL_DOCKER=1
INSTALL_GUI_APPS=1
INSTALL_OPENSSH_SERVER=1
INSTALL_SGX_SDK=1
INSTALL_GRAMINE=1
INSTALL_FORTANIX_EDP=1
INSTALL_RUST=1
INSTALL_PYTHON=1
ENABLE_GIT_GPG_COMMIT_SIGNING=1
ALLOW_OPENSSH_PASSWORD_AUTH=0
ALLOW_OPENSSH_PUBKEY_AUTH=1
RUST_CHANNEL="nightly"

PREREQUISITES=( curl )
NEED_RESTART=0

if [[ $USER != $MY_USER ]]; then
  INTERACTIVE=1
  echo "This script is configured for $MY_USER. However, you are logged in as $USER, so you will be prompted for your own info interactively. Alternatively, you can customize the defaults in bootstrap-ubuntu.sh."

  read -r -p "Do you want to continue and enter your own info interactively? [y/N] " yesno
  if [[ ! (${yesno,,} =~ ^(y|yes)$) ]]; then
    exit
  fi

  MY_USER=$USER
  GH_USERID=$USER
  GH_EMAIL="$USER@gmail.com"
  GIT_NAME=$USER
  KEY_FILE=$HOME/Downloads/Secret.asc
  TRUST_FILE=$HOME/Downloads/otrust.lst
fi

# Directory the script is located in
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${BASEDIR}"

# Windows Subsystem for Linux
# Don't install GUI apps on WSL
if uname -r | grep -qi "microsoft"; then
  IS_WSL=1
  INSTALL_GUI_APPS=0
fi

# Ubuntu release
RELEASE="$(lsb_release -sc)"

# Figure out release-specific requirements such as python version
if [[ $RELEASE == "noble" ]]; then
  # Ubuntu 24.04
  PYTHON_VER="python3.12"
elif [[ $RELEASE == "jammy" ]]; then
  # Ubuntu 22.04
  PYTHON_VER="python3.10"
else
  echo "Unsupported release $RELEASE!"
  exit
fi

# Start building the packages list
PACKAGES="$EXTRA_PACKAGES $DEV_PACKAGES"

# Install prerequisites for this script
for pkg in ${PREREQUISITES[@]}; do
  if [[ -z $(apt -qq list $pkg 2>/dev/null) ]]; then
    sudo apt install -y $pkg
  fi
done

# For installing package sources
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

# Python and venv; also prerequisites for gramine dev
if [[ $INSTALL_PYTHON == 1 || $INSTALL_GRAMINE == 1 ]]; then
  PACKAGES="$PACKAGES $PYTHON_VER-venv"
  INSTALLING_PYTHON=1
fi

# Docker
if [[ $INSTALL_DOCKER == 1 && -z $(which docker) ]]; then
  PACKAGES="$PACKAGES docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

  add_package_source \
    https://download.docker.com/linux/ubuntu/gpg \
    https://download.docker.com/linux/ubuntu $(lsb_release -sc) stable \
    docker.asc \
    docker.list

  INSTALLING_DOCKER=1
  NEED_RESTART=1
fi

# SGX; also a prerequisite for Gramine
if [[ ($INSTALL_SGX == 1 || $INSTALL_GRAMINE == 1) && ! -f /etc/sgx_default_qcnl.conf ]]; then
  PACKAGES="$PACKAGES
    cpuid libsgx-quote-ex libsgx-dcap-ql
    libsgx-dcap-quote-verify-dev libsgx-dcap-default-qpl-dev"

  add_package_source \
    https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key \
    https://download.01.org/intel-sgx/sgx_repo/ubuntu $(lsb_release -sc) main \
    intel-sgx-deb.asc \
    intel-sgx.list

  INSTALLING_SGX=1
  NEED_RESTART=1
fi

# Gramine
if [[ $INSTALL_GRAMINE == 1 && ! $(apt -qq list gramine 2>/dev/null) ]]; then
  PACKAGES="$PACKAGES gramine"

  add_package_source \
    https://packages.gramineproject.io/gramine-keyring-$(lsb_release -sc).gpg \
    https://packages.gramineproject.io $(lsb_release -sc) main \
    gramine-keyring-$(lsb_release -sc).gpg \
    gramine.list

  INSTALLING_GRAMINE=1
fi

# Install these GUI applications unless on WSL
# VSCode
if [[ $INSTALL_GUI_APPS == 1 && -z $(which code) ]]; then
  PACKAGES="$PACKAGES code"

  add_package_source \
    https://packages.microsoft.com/keys/microsoft.asc \
    https://packages.microsoft.com/repos/code stable main \
    packages.microsoft.asc \
    vscode.list
  INSTALLING_CODE=1
fi
# Brave Browser
if [[ $INSTALL_GUI_APPS == 1 && -z $(which brave-browser) ]]; then
  PACKAGES="$PACKAGES brave-browser"

  add_package_source \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/ stable main \
    brave-browser-archive-keyring.gpg \
    brave-browser-release.list
  INSTALLING_BRAVE=1
fi

if [[ $INSTALL_OPENSSH_SERVER == 1 && -z $(which sshd) ]]; then
  PACKAGES="$PACKAGES openssh-server"
  INSTALLING_OPENSSH_SERVER=1
fi

# Rust is required by Fortanix EDP
if [[ ($INSTALL_RUST == 1 || $INSTALL_FORTANIX_EDP == 1) && -z $(which rustc) ]]; then
  INSTALLING_RUST=1
fi

if [[ $INSTALL_FORTANIX_EDP == 1 && -z $(which sgx-detect) ]]; then
  PACKAGES="$PACKAGES pkg-config libssl-dev protobuf-compiler"
  INSTALLING_FORTANIX_EDP=1
  RUST_CHANNEL="nightly"
fi

# Only install packages that are not already installed.
PACKAGES_TO_INSTALL=""
IFS=';' read -ra pkgs <<< "$IN"
for pkg in "${pkgs[@]}"; do
  if [[ ! $(apt -qq list $pkg 2>/dev/null) ]]; then
    PACKAGES_TO_INSTALL=$PACKAGES_TO_INSTALL $pkg
  fi
done

if [[ -n $PACKAGES_TO_INSTALL ]]; then
  # Apply new package lists, and update software
  sudo apt update && sudo apt upgrade -y
  # Install software
  sudo apt install -y $PACKAGES_TO_INSTALL
fi

# Configure docker
if [[ $INSTALLING_DOCKER == 1 ]]; then
  sudo usermod -aG docker $USER
fi

# Configure SSH
if [[ ! -f $HOME/.ssh/id_ed25519 ]]; then
  ssh-keygen -t ed25519 -q -f "$HOME/.ssh/id_ed25519" -N "" -C "${GH_EMAIL}"
  cat ~/.ssh/id_ed25519.pub
  if [[ $INTERACTIVE == 1 ]]; then
    read -n 1 -p "Save the SSH public key in GitHub and in remote authorized_keys files, and press any key to continue"
  fi

  eval "$(ssh-agent -s)"
fi

# Set OpenSSH to start at boot
if [[ $INSTALLING_OPENSSH_SERVER == 1 ]]; then
  sudo systemctl enable ssh
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
  if [[ $(cat /etc/ssh/sshd_config | grep -i "$1 $old_val") ]]; then
    sudo sed -s -i "s/$1 $old_val/$1 $new_val/" /etc/ssh/sshd_config
    echo 1  # setting was changed
  else
    echo 0
  fi
}

# Update on every run
if [[ $INSTALL_OPENSSH_SERVER == 1 ]]; then
  pass_auth_changed=$(openssh_option PasswordAuthentication $ALLOW_OPENSSH_PASSWORD_AUTH)
  key_auth_changed=$(openssh_option PubkeyAuthentication $ALLOW_OPENSSH_PUBKEY_AUTH)
  # Restart ssh server if any settings changed
  if [[ $pass_auth_changed == 1 || $key_auth_changed == 1 ]]; then
    sudo systemctl try-reload-or-restart ssh
  fi
  ssh-import-id-gh $GH_USERID 2>/dev/null
fi

# Configure git; update on every run
git config --global user.email "${GH_EMAIL}"
git config --global user.name "${GIT_NAME}"

# Configure GPG & git signing; update on every run
export KEY_FILE TRUST_FILE INTERACTIVE ENABLE_GIT_GPG_COMMIT_SIGNING && \
  ./import-gpg-key.sh

# Install rust; prerequisite for Fortanix EDP
if [[ $INSTALLING_RUST == 1 ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s --   -y --default-toolchain $RUST_CHANNEL
  source "$HOME/.cargo/env"
fi

# Configure SGX
if [[ $INSTALLING_SGX == 1 ]]; then
  sudo usermod -aG sgx $USER
  sudo sed -s -i 's/localhost:8081/api.trustedservices.intel.com/' /etc/sgx_default_qcnl.conf
fi

# On every run
if [[ $INSTALLING_GRAMINE == 1 ]]; then
  if [[ ! -f $HOME/.config/gramine/enclave-key.pem ]]; then
    gramine-sgx-gen-private-key
  fi
fi

# Install Fortanix EDP
if [[ $INSTALLING_FORTANIX_EDP == 1 ]]; then
  # Nightly toolchain is required to be the default to install Fortanix EDP
  if [[ ! $(rustup toolchain list | grep 'nightly.*default') ]]; then
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

# Only on WSL for VSCODE: `public key decryption failed: Inappropriate ioctl for device`
# This fix still fails (I think `public key decryption failed: Invalid IPC response`)
if [[ $IS_WSL == 1 ]] then
  sync gpg.conf ../WSL/.gnupg ~/.gnupg
  sync gpg-agent.conf ../WSL/.gnupg ~/.gnupg
  echo RELOADAGENT | gpg-connect-agent
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