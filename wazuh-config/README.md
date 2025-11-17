# Wazuh Configuration Files

This directory contains custom Wazuh configuration files that will be deployed during setup.

## Files:

### `ossec.conf`
Main Wazuh manager configuration file. This file will be copied to `/var/ossec/etc/ossec.conf` on the k3s-master node during installation.

**To customize:**
1. Edit `ossec.conf` with your desired settings
2. Run the setup script - it will automatically deploy your custom config

**Example customizations:**
- Enable/disable specific modules
- Configure active response rules
- Set up email alerts
- Configure syslog output
- Adjust file integrity monitoring settings

### `agent.conf`
Centralized agent configuration. This is pushed from the manager to all connected agents.

**To customize:**
1. Edit `agent.conf` with centralized agent settings
2. Run the setup script

## Configuration Examples:

### Enable Active Response (in ossec.conf):
```xml
<active-response>
  <command>firewall-drop</command>
  <location>local</location>
  <rules_id>5710,5711,5712</rules_id>
  <timeout>600</timeout>
</active-response>
```

### Configure Email Alerts (in ossec.conf):
```xml
<global>
  <email_notification>yes</email_notification>
  <smtp_server>smtp.example.com</smtp_server>
  <email_from>wazuh@example.com</email_from>
  <email_to>admin@example.com</email_to>
</global>
```

### Monitor Custom Log Files (in agent.conf):
```xml
<agent_config>
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/myapp.log</location>
  </localfile>
</agent_config>
```

## Deployment:

The setup script will automatically:
1. Check if `ossec.conf` exists in this directory
2. If found, copy it to the Wazuh manager
3. Restart the manager to apply changes
4. Same for `agent.conf` and other config files

## Getting the Default Config:

To export the current configuration as a template:
```bash
incus exec k3s-master -- cat /var/ossec/etc/ossec.conf > wazuh-config/ossec.conf
incus exec k3s-master -- cat /var/ossec/etc/shared/agent.conf > wazuh-config/agent.conf
```
