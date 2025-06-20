## Advanced Troubleshooting

If the IP isn't being blocked as expected, let's systematically troubleshoot the issue. Here are the key steps to diagnose and fix the problem:

---

### **1. Verify IPset Membership**
```bash
sudo ipset list blacklist | grep '1.1.1.1'  # Replace with your test IP
```
- ✅ **Expected**: Should show the IP in the set  
- ❌ **If missing**: The IP wasn't added correctly

---

### **2. Check Firewalld Rules**
```bash
sudo firewall-cmd --list-rich-rules | grep ipset=blacklist
```
- ✅ **Expected Output**:  
  `rule source ipset="blacklist" drop`

- ❌ **If missing**: Add the rule:  
  ```bash
  sudo firewall-cmd --permanent --zone=public --add-rich-rule='rule source ipset=blacklist drop'
  sudo firewall-cmd --reload
  ```

---

### **3. Test Raw IPset Blocking (Bypass Firewalld)**
```bash
# Manually add to IPset
sudo ipset add blacklist 1.1.1.1

# Verify kernel-level blocking
sudo iptables -vL | grep blacklist
ping -c 3 1.1.1.1
```
- ✅ **Expected**: 100% packet loss  
- ❌ **If packets pass**: Your kernel may not support IPset (unlikely on modern systems)

---

### **4. Check for Whitelist Conflicts**
```bash
sudo ipset list whitelist 2>/dev/null | grep '1.1.1.1'
```
- ❌ **If found**: Remove with:  
  ```bash
  sudo ipset del whitelist 1.1.1.1
  ```

---

### **5. Inspect Firewall Logs**
```bash
# Enable logging temporarily
sudo firewall-cmd --add-rich-rule='rule source ipset=blacklist log prefix="BLOCKED: " level=notice'
sudo firewall-cmd --reload

# Monitor logs (in a new terminal)
sudo journalctl -f

# Generate traffic (in original terminal)
ping -c 3 1.1.1.1
curl -m 3 http://1.1.1.1
```
- ✅ **Expected Log**:  
  `BLOCKED: IN=... SRC=1.1.1.1 DST=...`

---

### **6. Common Fixes**

#### **A. Timeout Issues**
```bash
# Increase IPset timeout (default 86400 sec = 24h)
sudo ipset create blacklist hash:net timeout 3600  # 1 hour timeout
```

#### **B. Firewalld Not Using IPset**
```bash
# Verify IPset is in firewalld's direct rules
sudo firewall-cmd --direct --get-all-rules | grep blacklist
```

#### **C. IPset Type Mismatch**
```bash
# Ensure correct IPset type (hash:net for CIDR blocks)
sudo ipset list -t blacklist
```
- Must show `Type: hash:net`

---

### **7. Complete Test Workflow**
```bash
# 1. Clean test environment
sudo ipset flush blacklist

# 2. Add test IP
sudo ipset add blacklist 1.1.1.1

# 3. Verify
sudo ipset test blacklist 1.1.1.1  # Must return "is in set"
ping -c 3 1.1.1.1                 # Must show 100% loss

# 4. Check firewall
sudo iptables -vL | grep blacklist -A 3
```

---

### **Troubleshooting Table**

| Symptom                  | Likely Cause                     | Solution                          |
|--------------------------|----------------------------------|-----------------------------------|
| IP in ipset but not blocked | Missing firewalld rich rule      | Add drop rule and reload firewalld|
| IP disappears after reboot | IPset not persistent             | Use `ipset save/restore`          |
| Partial blocking          | Whitelist conflict               | Check whitelist IPsets            |
| Timeout too short         | Default timeout expired          | Increase with `timeout` parameter |

---

### **Final Verification**
If all else fails, test with **tcpdump**:
```bash
# Terminal 1: Monitor traffic
sudo tcpdump -ni any host 1.1.1.1

# Terminal 2: Generate traffic
ping -c 3 1.1.1.1
```
- ✅ **Blocked**: No reply packets  
- ❌ **Not Blocked**: You'll see ICMP replies

---

### **Persistent Configuration**
To make changes survive reboots:
```bash
# Save IPset
sudo ipset save > /etc/ipset.rules

# Restore on boot (add to crontab @reboot or systemd service)
ipset restore < /etc/ipset.rules
```

Would you like me to provide specific commands to check your current firewall state? Just share the output of:
```bash
sudo ipset list blacklist
sudo firewall-cmd --list-all
sudo iptables -vL
```
