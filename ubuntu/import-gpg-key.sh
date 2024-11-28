#!/bin/bash
set -e

GH_EMAIL=$(git config --global user.email)
if [[ -z $GH_EMAIL ]]; then
    echo "Must set \"git config --global user.email <email>\". run import-gpg-key.sh in dotfiles again later."
    return 1
fi

IMPORTED=$(gpg --list-keys | grep $GH_EMAIL)

if [[ ! $IMPORTED ]]; then
    if [[ $INTERACTIVE != "0" ]]; then
        read -r -p "Do you want to import your gpg key now? [Y/n] " yesno
        if [[ -n ${yesno} && ! ${yesno,,} =~ ^(y|yes)$ ]]; then
            exit
        fi

        read -p "File name for import [${KEY_FILE}]: " key_file
        key_file=${key_file:-"${KEY_FILE}"}
        if [[ -z $key_file || ! -f $key_file ]]; then
            echo Invalid filename $key_file
            return 1
        fi

        read -p "Owner trust file name for import [${TRUST_FILE}]: " trust_file
        trust_file=${trust_file:-"${TRUST_FILE}"}
        if [[ -z $trust_file || ! -f $trust_file ]]; then
            echo Invalid filename $trust_file
            return 1
        fi
    fi
fi

# Update git config
if [[ $ENABLE_GIT_GPG_COMMIT_SIGNING ]]; then
    if [[ ! $IMPORTED ]]; then
        # Import the key
        gpg --import "${key_file}"

        # Import trust file
        gpg --import-ownertrust "${trust_file}"
    fi

    git config --global user.signingkey "${GH_EMAIL}"
    git config --global commit.gpgsign true
else
    git config --global --unset user.signingkey
    git config --global --unset commit.gpgsign
fi
