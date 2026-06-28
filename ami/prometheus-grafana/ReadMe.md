# Prometheus & Grafana AMI Resources

This directory contains resources for deploying and configuring the Prometheus & Grafana Monitoring AMI from AWS Marketplace.

## Overview

Our Prometheus & Grafana AMI provides a production-ready monitoring solution with:
- **Prometheus** - Time-series database with automatic EC2 instance discovery
- **Grafana** - Pre-configured dashboards for visualizing metrics
- **Node Exporter** - System metrics collection from monitored instances
- **Automatic Discovery** - Monitors EC2 instances tagged with `vm_monitor=true`

## Quick Start Guide

### Step 1: Deploy IAM Roles (Recommended)

For Prometheus to automatically discover EC2 instances across your AWS account, deploy the IAM roles:

```bash
aws cloudformation create-stack \
  --stack-name prometheus-monitoring-iam \
  --template-body file://cloudformation/iam_role_policy_setup.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```

**Note**: This step is optional but highly recommended for automatic EC2 discovery.

### Step 2: Launch the AMI

1. Subscribe to the Prometheus & Grafana AMI in AWS Marketplace
2. Launch the instance with:
   - Recommended instance type: t3.medium or larger
   - Security group allowing:
     - Port 22 (SSH)
     - Port 3000 (Grafana)
     - Port 9090 (Prometheus)
   - IAM role created in Step 1 (if using automatic discovery)

### Step 3: Install Node Exporter on Target Instances

For each EC2 instance you want to monitor:

```bash
# Download the installation script
curl -O https://raw.githubusercontent.com/[your-org]/aws-ami-resources/main/prometheus-grafana/scripts/install_node_exporter.sh

# Make it executable
chmod +x install_node_exporter.sh

# Run the installation
sudo ./install_node_exporter.sh
```

The script will:
- Install Node Exporter as a systemd service
- Configure it to run on port 9100
- Optionally tag the instance with `vm_monitor=true` (if AWS CLI is configured)

### Step 4: Configure Instance Discovery

#### Option A: Automatic Discovery (Recommended)
Tag your instances with:
```bash
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=vm_monitor,Value=true
```

#### Option B: Manual Configuration
SSH into the Prometheus server and edit `/opt/prometheus/config/prometheus.yml` to add static targets.

### Step 5: Access the Monitoring Stack

- **Prometheus**: `http://[your-instance-ip]:9090`
  - View discovered targets at `/targets`
  - Query metrics and create alerts
  
- **Grafana**: `http://[your-instance-ip]:3000`
  - Default credentials: `admin/admin`
  - Pre-configured Node Exporter dashboard
  - Prometheus datasource already configured

## Directory Structure

```
prometheus-grafana/
├── cloudformation/
│   ├── iam_role_policy_setup.yaml    # IAM roles for EC2 discovery
│   └── usage.md                      # CloudFormation template documentation
├── scripts/
│   └── install_node_exporter.sh      # Node Exporter installation script
└── README.md                         # This file
```

## Security Considerations

1. **Change default credentials** immediately after first login to Grafana
2. **Restrict security groups** to allow access only from trusted IP ranges
3. **Enable HTTPS** for production deployments (consider using ALB or nginx)
4. **Review IAM permissions** in the CloudFormation template before deployment

## Monitoring Configuration

### Prometheus Configuration
- Configuration file: `/opt/prometheus/config/prometheus.yml`
- Data directory: `/opt/prometheus/data`
- Service: `systemctl status prometheus`

### Grafana Configuration
- Configuration file: `/etc/grafana/grafana.ini`
- Service: `systemctl status grafana-server`

### Pre-configured Alerts
The AMI includes the following alerts:
- Instance Down (5 minutes)
- High CPU Usage (>80% for 10 minutes)
- High Memory Usage (>85% for 10 minutes)
- High Disk Usage (>85% for 10 minutes)
- Predictive Disk Full (24 hours)

## Troubleshooting

### Instances Not Appearing in Prometheus

1. Verify the instance has tag `vm_monitor=true`:
   ```bash
   aws ec2 describe-tags --filters "Name=resource-id,Values=i-xxxxx"
   ```

2. Check Node Exporter is running:
   ```bash
   sudo systemctl status node_exporter
   curl http://localhost:9100/metrics
   ```

3. Ensure security groups allow traffic:
   - Prometheus server → Target instance on port 9100
   - Your IP → Prometheus server on ports 3000, 9090

4. Check Prometheus logs:
   ```bash
   sudo journalctl -u prometheus -f
   ```

### Grafana Login Issues

Reset admin password:
```bash
sudo grafana-cli admin reset-admin-password newpassword
sudo systemctl restart grafana-server
```

## Advanced Configuration

### Adding Custom Dashboards
1. Access Grafana UI
2. Navigate to Dashboards → Import
3. Upload JSON or enter dashboard ID from [Grafana.com](https://grafana.com/grafana/dashboards/)

### Configuring Alertmanager
Edit `/opt/prometheus/config/prometheus.yml` to add Alertmanager configuration.

### Cross-Account Monitoring
Ensure the IAM role has permissions to discover instances in other accounts using assume role policies.

## Support

For issues specific to:
- **This repository**: Open a GitHub issue
- **The AMI**: Contact through AWS Marketplace support
- **Prometheus/Grafana**: Refer to official documentation

## Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Node Exporter GitHub](https://github.com/prometheus/node_exporter)
- [AWS EC2 Service Discovery](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#ec2_sd_config)
