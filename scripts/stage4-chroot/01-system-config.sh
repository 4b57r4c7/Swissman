# Basic system configuration (LFS chapter 9, systemd edition).
cat > /etc/os-release << "EOF2"
NAME="Swissman"
ID=swissman
PRETTY_NAME="Swissman Linux"
VERSION_ID="0.1"
HOME_URL="https://github.com/4b57r4c7/Swissman"
EOF2

echo swissman > /etc/hostname
echo "LANG=C.UTF-8" > /etc/locale.conf

cat > /etc/shells << "EOF2"
/bin/sh
/bin/bash
EOF2

# The root file system is found and mounted by the initramfs.
cat > /etc/fstab << "EOF2"
# file system  mount-point  type  options  dump  fsck-order
EOF2

# DHCP on any wired interface.
mkdir -pv /etc/systemd/network
cat > /etc/systemd/network/10-wired-dhcp.network << "EOF2"
[Match]
Type=ether

[Network]
DHCP=yes
EOF2
systemctl enable systemd-networkd systemd-resolved
ln -sfv /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Chapter 8 generated a machine ID inside the build; every copy of the
# image must get its own, so let systemd create one on first boot.
: > /etc/machine-id
