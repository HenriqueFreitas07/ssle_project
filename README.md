# SSLE Project - Wazuh Attack Detection Lab

A complete security lab environment for detecting and responding to web attacks (Shellshock, DoS, APT) using Wazuh SIEM, deployed on a K3s cluster with Incus containers.

---

## Project Structure

```
ssle_project/
├── docker-compose.yml              # Docker Compose for local microservices
├── pyproject.toml                  # Python project configuration
├── poetry.lock                     # Poetry dependency lock file
│
├── k8s/                            # Kubernetes manifests
│   ├── namespace.yaml              # Namespace definition
│   ├── configmaps.yaml             # Configuration maps
│   ├── storage-pvc.yaml            # Persistent volume claims
│   ├── prometheus.yaml             # Prometheus monitoring
│   ├── grafana.yaml                # Grafana dashboards
│   ├── registry-service.yaml       # Registry microservice
│   ├── storage-service.yaml        # Storage microservice
│   ├── ingestion-service.yaml      # Ingestion microservice
│   ├── analytics-service.yaml      # Analytics microservice
│   └── temperature-service.yaml    # Temperature sensor service
│
├── src/ssle_project/               # Python microservices source code
│   ├── registry_service/           # Service registry API
│   ├── storage_service/            # Data storage service
│   ├── ingestion_service/          # Data ingestion service
│   ├── analytics_service/          # Data analytics service
│   └── temperature_service/        # Temperature sensor simulator
│
├── wazuh-config/                   # Wazuh SIEM configuration
│   ├── ossec.conf                  # Wazuh manager configuration
│   ├── agent-config.conf           # Wazuh agent configuration
│   ├── local_rules.xml             # Custom detection rules (25+)
│   ├── action.conf                 # Active response actions
│   ├── mpm_event.conf              # Apache MPM configuration
│   ├── ATTACK_DETECTION_SUMMARY.md # Rule documentation
│   └── QUICK_REFERENCE.md          # Quick lookup guide
│
├── tests/                          # Test files
├── screenshots/                    # Documentation screenshots
│
├── setup-complete-cluster.sh       # Main setup script
├── setup-incus-attacker.sh         # Attacker container setup
├── run-attack-tests.sh             # Attack simulation script
├── update_wazuh.sh                 # Wazuh config update utility
├── incus-network-fix.sh            # Network troubleshooting
│
├── ATTACK_SIMULATION_GUIDE.md      # Comprehensive attack guide
├── INCUS_TESTING_GUIDE.md          # Incus-specific testing guide
└── LLM_REPORT_PROMPT.md            # Report generation prompt
```

---

## Shell Scripts

### setup-complete-cluster.sh

The main orchestration script that builds the entire lab environment from scratch. It performs 12 automated steps:

1. Configures host kernel parameters for K3s compatibility
2. Creates an Incus profile with security settings for K3s
3. Launches a K3s master node on Debian Trixie
4. Creates and joins worker nodes (k3s-node1, k3s-node2)
5. Labels nodes for workload scheduling
6. Creates an Apache container with Wazuh agent
7. Installs Wazuh (manager, indexer, dashboard) in a dedicated container
8. Applies custom detection rules and ossec.conf
9. Builds and imports Docker images into K3s nodes
10. Deploys Prometheus and Grafana monitoring stack
11. Deploys all microservices to the cluster
12. Installs Wazuh agents on all worker nodes

**Requires:** sudo privileges, Incus, Docker

---

### setup-incus-attacker.sh

Creates an Ubuntu-based attacker container with pre-installed penetration testing tools. The container includes:

- Network tools: curl, wget, netcat, nmap, hping3, tcpdump
- Security scanners: nikto, sqlmap
- Python attack tools: slowloris
- Standard utilities: traceroute, telnet, dnsutils

The script automatically detects your Apache container IP and provides quick-start commands for testing.

---

### run-attack-tests.sh

An interactive attack simulation script with multiple test categories:

| Test Type | Description |
|-----------|-------------|
| `shellshock` | Sends Shellshock payloads in HTTP headers |
| `dos-light` | Moderate HTTP flood (60-100 requests) |
| `dos-heavy` | Aggressive flood (120-250 requests) |
| `apt-recon` | Directory scanning, vulnerability probing |
| `apt-exploit` | SQL injection, XSS, command injection, LFI |
| `apt-persist` | Web shell uploads, obfuscated payloads |
| `all` | Runs all tests sequentially |

**Usage:** `./run-attack-tests.sh <apache_ip> <test_type>`

---

### update_wazuh.sh

A utility script for applying configuration changes to Wazuh without rebuilding the entire cluster. It:

1. Reads local `ossec.conf` and `local_rules.xml` files
2. Substitutes the manager IP address automatically
3. Pushes configurations to the Wazuh container
4. Restarts the Wazuh manager service
5. Verifies the service is running correctly

Useful for iterating on detection rules during development.

---

### incus-network-fix.sh

Diagnoses and fixes networking issues when Docker and Incus coexist. The script:

1. Checks incusbr0 bridge configuration
2. Verifies IP forwarding is enabled
3. Tests container connectivity to external networks
4. Adds iptables FORWARD and NAT rules if needed
5. Provides persistence recommendations

**Requires:** sudo privileges

---

## Setup Tutorial

### Prerequisites

- Linux host (tested on Manjaro/Arch)
- Incus container manager installed and configured
- Docker and Docker Compose
- At least 8GB RAM available
- Sudo access

### Step 1: Clone and Navigate

```bash
cd ~/Desktop/ssle_project
```

### Step 2: Run the Complete Setup

```bash
sudo ./setup-complete-cluster.sh
```

This takes 10-20 minutes depending on your network speed. The script will:
- Create all necessary containers
- Install K3s cluster
- Deploy Wazuh SIEM
- Deploy monitoring stack
- Configure attack detection rules

At the end, the script outputs:
- Wazuh Dashboard URL and credentials
- Cluster status
- Service endpoints

### Step 3: Verify the Deployment

Check all containers are running:

```bash
incus list
```

Expected containers:
- `k3s-master` - Kubernetes master node
- `k3s-node1`, `k3s-node2` - Worker nodes
- `wazuh-container` - Wazuh SIEM
- `apache-container` - Target web server

Check K8s pods:

```bash
incus exec k3s-master -- k3s kubectl get pods -n ssle-project
incus exec k3s-master -- k3s kubectl get pods -n monitoring
```

### Step 4: Access Wazuh Dashboard

Open your browser and navigate to:

```
https://<wazuh-container-ip>
```

Default credentials are displayed at the end of the setup script. If you need them again:

```bash
incus exec wazuh-container -- cat wazuh-install-files/wazuh-passwords.txt
```

### Step 5: Create the Attacker Container

```bash
./setup-incus-attacker.sh
```

### Step 6: Run Your First Attack Test

Get the Apache container IP:

```bash
incus list apache-container -c 4
```

Run a Shellshock test:

```bash
incus exec attacker -- curl -H "User-Agent: () { :; }; echo test" http://<apache_ip>/
```

Monitor alerts in real-time:

```bash
incus exec wazuh-container -- tail -f /var/ossec/logs/alerts/alerts.log
```

---

## Attack Detection Coverage

### Shellshock (Rules 100100-100102)
- Pattern detection in HTTP headers
- Command execution attempts
- 30-minute IP block on detection

### DoS Attacks (Rules 100200-100206)
- HTTP flood detection (50-250 req/s thresholds)
- Slowloris attack detection
- 5-10 minute IP blocks

### APT Attacks (Rules 100300-100312)
- Reconnaissance: directory scanning, vulnerability probing
- Exploitation: SQLi, XSS, command injection, LFI
- Persistence: web shells, obfuscated payloads
- 30-60 minute IP blocks

---

## Common Commands

```bash
# List all containers
incus list

# Access a container shell
incus exec <container-name> -- bash

# View Wazuh alerts
incus exec wazuh-container -- tail -f /var/ossec/logs/alerts/alerts.log

# Check agent status
incus exec wazuh-container -- /var/ossec/bin/agent_control -l

# View blocked IPs on Apache
incus exec apache-container -- iptables -L INPUT -n | grep DROP

# Unblock an IP
incus exec apache-container -- iptables -D INPUT -s <ip> -j DROP

# Update Wazuh config after changes
./update_wazuh.sh
```

---

## Cleanup

Stop and remove the attacker container:

```bash
incus stop attacker && incus delete attacker
```

Remove the entire lab (warning: destroys all data):

```bash
incus stop --all
incus delete k3s-master k3s-node1 k3s-node2 wazuh-container apache-container
```

---

## Troubleshooting

### Network Issues

If containers cannot reach external networks:

```bash
sudo ./incus-network-fix.sh
```

### Wazuh Not Detecting Attacks

1. Verify the agent is connected:
   ```bash
   incus exec wazuh-container -- /var/ossec/bin/agent_control -l
   ```

2. Check rules are loaded:
   ```bash
   incus exec wazuh-container -- cat /var/ossec/etc/rules/local_rules.xml
   ```

3. Test rule parsing:
   ```bash
   incus exec wazuh-container -- /var/ossec/bin/wazuh-logtest
   ```

### IP Already Blocked

If you blocked yourself during testing:

```bash
incus exec apache-container -- iptables -F INPUT
```

---

## Additional Documentation

- `INCUS_TESTING_GUIDE.md` - Detailed Incus testing procedures
- `ATTACK_SIMULATION_GUIDE.md` - Comprehensive attack documentation
- `wazuh-config/QUICK_REFERENCE.md` - Rule quick reference
- `wazuh-config/ATTACK_DETECTION_SUMMARY.md` - Full rule documentation

---

## Warnings

- Only test on systems you own or have explicit authorization to test
- DoS tests can impact service availability
- IP blocks last 5-60 minutes depending on attack severity
- Monitor system resources during heavy tests

---

**Environment:** Incus containers, K3s, Wazuh 4.x, Apache 2.4
**Last Updated:** 2025-11-22
