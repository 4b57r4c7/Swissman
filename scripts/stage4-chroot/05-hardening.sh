# System hardening: a default-deny firewall and safer kernel settings.

# Firewall: drop every incoming connection we did not start. Outgoing
# traffic is allowed.
cat > /etc/nftables.conf << "EOF2"
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority filter; policy drop;
    iif "lo" accept
    ct state invalid drop
    ct state established,related accept
    # IPv6 does not work without neighbour discovery and router adverts.
    icmpv6 type { destination-unreachable, packet-too-big, time-exceeded,
                  parameter-problem, nd-router-advert, nd-neighbor-solicit,
                  nd-neighbor-advert } accept
    icmp type { destination-unreachable, time-exceeded, parameter-problem } accept
    # DHCPv6 replies come from a link-local server address.
    ip6 saddr fe80::/10 udp sport 547 udp dport 546 accept
  }
  chain forward {
    type filter hook forward priority filter; policy drop;
  }
  chain output {
    type filter hook output priority filter; policy accept;
  }
}
EOF2
chmod 600 /etc/nftables.conf

# Load the rules before any network interface comes up.
cat > /usr/lib/systemd/system/nftables.service << "EOF2"
[Unit]
Description=nftables firewall
Wants=network-pre.target
Before=network-pre.target shutdown.target
Conflicts=shutdown.target
DefaultDependencies=no

[Service]
Type=oneshot
RemainAfterExit=yes
StandardInput=null
ProtectSystem=full
ProtectHome=true
ExecStart=/usr/sbin/nft -f /etc/nftables.conf
ExecReload=/usr/sbin/nft -f /etc/nftables.conf
ExecStop=/usr/sbin/nft flush ruleset

[Install]
WantedBy=sysinit.target
EOF2
systemctl enable nftables

# Kernel settings, mostly from the Kernel Self Protection Project
# recommendations.
cat > /etc/sysctl.d/90-swissman.conf << "EOF2"
# Hide kernel addresses and the kernel log from unprivileged users.
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.printk = 3 3 3 3
# No BPF for unprivileged users, and harden the BPF JIT.
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
# Only root may attach a debugger to another process.
kernel.yama.ptrace_scope = 2
kernel.perf_event_paranoid = 2
kernel.sysrq = 0
dev.tty.ldisc_autoload = 0
# No core dumps from setuid programs; safer links and files in /tmp.
fs.suid_dumpable = 0
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
# Network: no redirects or source routing, reverse path filtering.
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF2
