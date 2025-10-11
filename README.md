# IPset Blacklist for Firewalld

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)  
**Atomic IP blocking with zero downtime** using ipsets and firewalld. Supports IPv4/IPv6 and CIDR optimization.

## Version
```
v2.0.0-alpha.4
```

## 🔥 Features
- **Zero-downtime updates** via atomic IPset swapping
- **IPv4/IPv6 dual-stack** support
- **CIDR merging** with `iprange` (optional)
- **Whitelist** for false positives
- **Firewalld integration** with rich rules
- **Configurable** timeout and max elements

## 📦 Installation

### Dependencies
```bash
# Required
sudo apt-get install ipset firewalld curl

# Recommended for CIDR optimization
sudo apt-get install iprange
```

### Install Script
```bash
sudo curl -o /usr/local/bin/update-blacklist.sh \
  https://raw.githubusercontent.com/nidhhoggr/ipset-blacklist-firewalld/master/update-blacklist.sh
sudo chmod +x /usr/local/bin/update-blacklist.sh
```

## ⚙️ Configuration
Copy the example config:
```bash
sudo curl -o /etc/ipset-blacklist-firewalld.conf \
  https://raw.githubusercontent.com/nidhhoggr/ipset-blacklist-firewalld/master/ipset-blacklist-firewalld.conf
```

### Config Options (`/etc/ipset-blacklist-firewalld.conf`)
```ini
# IPv4 Blacklists (URLs or local files)
BLACKLIST_URLS=(
  "https://lists.blocklist.de/lists/all.txt"
  "file:///path/to/local-list.txt"
)

# IPv6 Blacklists (optional)
BLACKLIST_V6_URLS=(
  "https://www.team-cymru.org/Services/Bogons/fullbogons-ipv6.txt"
)

# Whitelist (IPs/CIDRs to exclude)
WHITELIST=( "192.168.1.0/24" "10.0.0.1" )
WHITELIST_V6=( "2001:db8::/32" )

# Advanced
IPSET_NAME="blacklist"
IPSET_TIMEOUT="86400"  # 24h in seconds
MAXELEM="65536"       # Max IPs/CIDRs
```

## 🚀 Usage
```bash
# Dry-run (test config)
sudo update-blacklist.sh --dry-run

# Run update
sudo update-blacklist.sh

# Custom config location
sudo update-blacklist.sh --config /path/to/config.conf
```

## 🕵️‍♂️ Verification
```bash
# Check active IPset
sudo ipset list blacklist | head -n20

# Test if IP is blocked (should timeout)
ping -c 3 1.1.1.1

# View firewall logs
sudo journalctl -u firewalld -f | grep DROP
```

## 🔄 Automation
### Systemd Service/Timer
```bash
# Service file (/etc/systemd/system/ipset-blacklist.service)
[Unit]
Description=IPset Blacklist Update
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-blacklist.sh

# Timer file (/etc/systemd/system/ipset-blacklist.timer)
[Unit]
Description=Daily IPset Update

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

Enable with:
```bash
sudo systemctl enable --now ipset-blacklist.timer
```

## 🐛 Troubleshooting
### IPs Not Blocked?
1. Verify firewalld rule exists:
   ```bash
   sudo firewall-cmd --list-rich-rules | grep ipset
   ```
2. Check kernel module:
   ```bash
   lsmod | grep xt_set || sudo modprobe xt_set
   ```
3. Test raw IPset blocking:
   ```bash
   sudo ipset add blacklist 1.1.1.1
   ping -c 3 1.1.1.1  # Should fail
   ```

4. Still stuck? See [advanced troubleshooting](https://github.com/nidhhoggr/ipset-blacklist-firewalld/blob/master/troubleshooting.md)

### Performance Tips
```ini
# For large lists (>50k IPs)
MAXELEM="131072"
IPSET_TIMEOUT="43200"  # 12h
```

## 📜 License
MIT © nidhhoggr
