# Wazuh Attack Detection & Testing for Apache Server

Complete setup for detecting and responding to Shellshock, DoS, and APT attacks on Apache using Wazuh.

---

## 📁 Project Structure

```
ssle_project/
├── wazuh-config/
│   ├── local_rules.xml              # 25+ custom detection rules
│   ├── ossec.conf                   # Wazuh manager config with active response
│   ├── agent-config.conf            # Agent config with Apache monitoring
│   ├── ATTACK_DETECTION_SUMMARY.md  # Complete rule documentation
│   ├── QUICK_REFERENCE.md           # Fast lookup guide
│   └── README_TESTING.md            # Testing documentation hub
│
├── INCUS_TESTING_GUIDE.md           # ⭐ START HERE for Incus testing
├── ATTACK_SIMULATION_GUIDE.md       # Comprehensive attack simulation guide
├── TESTING_QUICK_START.md           # Generic quick start guide
│
├── setup-incus-attacker.sh          # ⭐ Incus attacker container setup
├── setup-attacker-container.sh      # Generic (Docker/K8s) setup
└── run-attack-tests.sh              # Automated attack testing script
```

---

## 🚀 Quick Start (Incus Environment)

### 1. Setup Attacker Container

```bash
cd /home/hfreitas07/Desktop/ssle_project
./setup-incus-attacker.sh
```

The script will:
- Create an Incus container named `attacker`
- Install all necessary tools
- Auto-detect your Apache container IP
- Show you next steps

### 2. Run Your First Test (Shellshock)

```bash
# Get your Apache IP from the setup script output, or:
incus list

# Run a simple Shellshock test
incus exec attacker -- curl -H "User-Agent: () { :; }; echo test" http://<APACHE_IP>/
```

### 3. Verify Detection

```bash
# On Wazuh manager, watch for alerts
incus exec wazuh-manager -- tail -f /var/ossec/logs/alerts/alerts.log | grep "Shellshock"

# On Apache container, check if IP was blocked
incus exec <apache-container> -- iptables -L INPUT -n | grep DROP
```

**Expected Result:**
- ✅ Wazuh alert: Rule 100100, Level 15 - "Shellshock attack detected"
- ✅ Attacker IP blocked for 30 minutes
- ✅ Subsequent requests fail/timeout

---

## 📚 Documentation

### For Testing (Choose Based on Your Environment)

**Using Incus?** → Read **INCUS_TESTING_GUIDE.md** ⭐ (Recommended for you!)

**Using Docker/Kubernetes?** → Read **TESTING_QUICK_START.md**

**Want comprehensive details?** → Read **ATTACK_SIMULATION_GUIDE.md**

### For Configuration Reference

**Quick rule lookup** → **wazuh-config/QUICK_REFERENCE.md**

**Complete documentation** → **wazuh-config/ATTACK_DETECTION_SUMMARY.md**

---

## 🎯 Attack Coverage

### Shellshock (Rules 100100-100102)
- Detects `() { :; };` patterns in requests
- Command execution attempts
- Header-based exploitation
- **Response:** 30-minute IP block

### DoS Attacks (Rules 100200-100206, 200xxx)
- HTTP floods: 50-250 req/s detection thresholds
- Slowloris attacks
- POST floods
- SYN floods, UDP floods
- **Response:** 5-10 minute IP blocks

### APT Attacks (Rules 100300-100312)
- **Reconnaissance:** Directory scanning, vulnerability scanning, scanner detection
- **Exploitation:** SQL injection, XSS, command injection, LFI
- **Persistence:** Web shells, obfuscated payloads, repeated attacks
- **Credential Access:** Brute force, sensitive file access
- **Data Exfiltration:** Large data transfers
- **Response:** 30-60 minute IP blocks

---

## 🛠️ Automated Testing

### Available Test Types

```bash
incus file push run-attack-tests.sh attacker/root/
incus exec attacker -- bash /root/run-attack-tests.sh <APACHE_IP> <TEST_TYPE>
```

| Test Type | Description | Impact |
|-----------|-------------|--------|
| `shellshock` | Shellshock vulnerability detection | Low, 30min block |
| `apt-recon` | Directory/vulnerability scanning | Low, no block |
| `apt-exploit` | SQL/XSS/Command injection | Low, 30min block |
| `apt-persist` | Web shells, obfuscation | Low, 60min block |
| `dos-light` | 50-100 req/s HTTP flood | Medium, 5-10min block |
| `dos-heavy` | 200+ req/s aggressive flood | High, 10min block |
| `all` | All tests (CAUTION) | High, multiple blocks |

---

## 📊 Example Test Session

```bash
# 1. Create attacker container
./setup-incus-attacker.sh

# 2. Find Apache IP
incus list
# Example output: apache-container  10.100.123.45

# 3. Monitor Wazuh alerts (in another terminal)
incus exec wazuh-manager -- tail -f /var/ossec/logs/alerts/alerts.log &

# 4. Run Shellshock test
incus exec attacker -- curl -H "User-Agent: () { :; }; echo test" http://10.100.123.45/

# 5. Verify blocking
incus exec apache-container -- iptables -L INPUT -n | grep DROP

# 6. Run automated tests
incus file push run-attack-tests.sh attacker/root/
incus exec attacker -- bash /root/run-attack-tests.sh 10.100.123.45 apt-recon
```

---

## ✅ Verification Checklist

- [ ] Wazuh manager running with custom rules loaded
- [ ] Apache container running with Wazuh agent
- [ ] Attacker container created successfully
- [ ] Apache IP identified
- [ ] Shellshock test triggers Rule 100100
- [ ] Attacker IP appears in iptables DROP rules
- [ ] Alerts visible in Wazuh dashboard
- [ ] Active responses logged

---

## 🔧 Common Incus Commands

```bash
# List all containers
incus list

# Access container
incus exec <container-name> -- bash

# Copy files to container
incus file push local-file.txt container-name/path/

# Copy files from container
incus file pull container-name/path/file.txt ./

# Stop/start container
incus stop <container-name>
incus start <container-name>

# Delete container
incus delete <container-name>
```

---

## 🐛 Troubleshooting

### No alerts appearing?
```bash
# Check Wazuh manager
incus exec wazuh-manager -- systemctl status wazuh-manager
incus exec wazuh-manager -- /var/ossec/bin/agent_control -l
```

### No IP blocking?
```bash
# Check active-response logs
incus exec wazuh-manager -- tail -f /var/ossec/logs/active-responses.log

# Check iptables on Apache
incus exec <apache-container> -- iptables -L -n -v
```

### Already blocked?
```bash
# Clear IP block
incus exec <apache-container> -- iptables -D INPUT -s <attacker-ip> -j DROP
```

More troubleshooting: See **INCUS_TESTING_GUIDE.md**

---

## 🧹 Cleanup

```bash
# Remove attacker container
incus stop attacker
incus delete attacker

# Clear IP blocks
incus exec <apache-container> -- iptables -F INPUT
```

---

## ⚠️ Important Warnings

- **Only test systems you own or have explicit authorization to test**
- DoS tests can impact service availability
- IP blocks can last 5-60 minutes
- Don't run all tests simultaneously
- Monitor resources during heavy tests

---

## 📖 Additional Resources

- **Incus Testing Guide:** INCUS_TESTING_GUIDE.md
- **Attack Simulation:** ATTACK_SIMULATION_GUIDE.md  
- **Rule Reference:** wazuh-config/QUICK_REFERENCE.md
- **Full Documentation:** wazuh-config/ATTACK_DETECTION_SUMMARY.md

---

**Created:** 2025-11-19  
**Environment:** Incus containers  
**Wazuh Version:** 4.x  
**Apache Version:** 2.4
