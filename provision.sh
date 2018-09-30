#!/bin/bash
set -eux


echo 'Defaults env_keep += "DEBIAN_FRONTEND"' >/etc/sudoers.d/env_keep_apt
chmod 440 /etc/sudoers.d/env_keep_apt
export DEBIAN_FRONTEND=noninteractive


#
# make sure the package index cache is up-to-date before installing anything.

apt-get update


# enable systemd-journald persistent logs.
sed -i -E 's,^#?(Storage=).*,\1persistent,' /etc/systemd/journald.conf
systemctl restart systemd-journald


#
# install vim.

apt-get install -y --no-install-recommends vim

cat >~/.vimrc <<'EOF'
syntax on
set background=dark
set esckeys
set ruler
set laststatus=2
set nobackup
EOF


#
# configure the shell.

cat >~/.bash_history <<'EOF'
EOF

cat >~/.bashrc <<'EOF'
# If not running interactively, don't do anything
[[ "$-" != *i* ]] && return

export EDITOR=vim
export PAGER=less

alias l='ls -lF --color'
alias ll='l -a'
alias h='history 25'
alias j='jobs -l'
EOF

cat >~/.inputrc <<'EOF'
"\e[A": history-search-backward
"\e[B": history-search-forward
"\eOD": backward-word
"\eOC": forward-word
set show-all-if-ambiguous on
set completion-ignore-case on
EOF


#
# install docker.
# see https://docs.docker.com/engine/installation/linux/ubuntu/#install-using-the-repository
# NB we can also install a specific version from https://download.docker.com/linux/ubuntu/dists/

apt-get install -y gnupg
apt-get install -y apt-transport-https #ca-certificates #software-properties-common
wget -qO- https://download.docker.com/linux/ubuntu/gpg | apt-key add -
[ -z "$(apt-key fingerprint 0EBFCD88 | grep '9DC8 5822 9FC7 DD38 854A  E2D8 8D81 803C 0EBF CD88')" ] && echo 'failed to verify docker apt repo fingerprint' && exit 1
echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) edge" >/etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce
docker version


#
# configure git.

git config --global user.name 'Rui Lopes'
git config --global user.email 'rgl@ruilopes.com'
git config --global push.default simple
git config --global core.autocrlf false


#
# install build dependencies.

apt-get install -y make


#
# clone linuxkit.

git clone https://github.com/linuxkit/linuxkit.git
cd linuxkit
git reset --hard 00aaf428d94b88352dd514a39fe5e86054d122b0


#
# build linuxkit.

make

# add to PATH.
cat >/etc/profile.d/linuxkit.sh <<EOF
export PATH="\$PATH:$PWD/bin"
EOF
source /etc/profile.d/linuxkit.sh

# show the built binary version.
linuxkit version


#
# build example iso (for bios and efi boot) and kernel+initrd (for pxe boot) images.

cd examples
# put a shell console on the machine console.
sed -i -E 's,(cmdline:).+,\1 "console=tty0",' sshd.yml
# add the default vagrant insecure key.
sed -i -E "s,source:.+,contents: \"$(wget -qO- https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub)\"," sshd.yml
# build it.
linuxkit build -format iso-bios,iso-efi,kernel+initrd sshd.yml


#
# copy built artefacts to the host, so we can use them from the host or other VMs.

mkdir -p /vagrant/shared
cp ../bin/linuxkit /vagrant/shared
cp sshd* /vagrant/shared
