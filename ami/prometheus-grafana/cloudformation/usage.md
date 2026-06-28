# Prometheus EC2 Discovery IAM Role - CloudFormation Template

## Overview

This CloudFormation template creates the necessary IAM role and permissions for your Prometheus instance to automatically discover and monitor EC2 instances across your AWS account.

## What This Template Creates

1. **IAM Role**: `PrometheusEC2DiscoveryRole` - Allows EC2 instances to assume this role
2. **IAM Policy**: `PrometheusEC2DiscoveryPolicy` - Grants EC2 discovery permissions
3. **Instance Profile**: `PrometheusEC2DiscoveryInstanceProfile` - Attaches the role to EC2 instances

## Permissions Granted

- `ec2:DescribeInstances` - Discover EC2 instances for monitoring
- `ec2:DescribeRegions` - List available AWS regions

## Deployment Instructions

### Option 1: AWS Console

1. **Download the template** from AWS Marketplace documentation
2. **Go to CloudFormation** in AWS Console
3. **Create Stack** → Upload template file
4. **Configure parameters** (or use defaults):
   - Role Name: `PrometheusEC2DiscoveryRole`
   - Instance Profile Name: `PrometheusEC2DiscoveryInstanceProfile`
5. **Deploy the stack**

### Option 2: AWS CLI

```bash
# Download the template file as prometheus-iam-role.yaml

# Deploy the stack
aws cloudformation create-stack \
    --stack-name prometheus-ec2-discovery-iam \
    --template-body file://prometheus-iam-role.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=RoleName,ParameterValue=PrometheusEC2DiscoveryRole \
                 ParameterKey=InstanceProfileName,ParameterValue=PrometheusEC2DiscoveryInstanceProfile

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name prometheus-ec2-discovery-iam \
    --query 'Stacks[0].StackStatus'
```

### Option 3: Terraform (Alternative)

```hcl
# If you prefer Terraform over CloudFormation
resource "aws_cloudformation_stack" "prometheus_iam" {
  name         = "prometheus-ec2-discovery-iam"
  template_body = file("prometheus-iam-role.yaml")
  
  capabilities = ["CAPABILITY_NAMED_IAM"]
  
  parameters = {
    RoleName            = "PrometheusEC2DiscoveryRole"
    InstanceProfileName = "PrometheusEC2DiscoveryInstanceProfile"
  }
}
```

## Attaching the Role to Your Prometheus Instance

### For New Instances

When launching your Prometheus instance from the AWS Marketplace AMI:

```bash
aws ec2 run-instances \
    --image-id ami-xxxxxxxxx \
    --instance-type t3.medium \
    --iam-instance-profile Name=PrometheusEC2DiscoveryInstanceProfile \
    --security-group-ids sg-xxxxxxxxx \
    --subnet-id subnet-xxxxxxxxx
```

### For Existing Instances

```bash
# Get the instance profile ARN from CloudFormation outputs
INSTANCE_PROFILE_NAME=$(aws cloudformation describe-stacks \
    --stack-name prometheus-ec2-discovery-iam \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceProfileName`].OutputValue' \
    --output text)

# Attach to existing instance
aws ec2 associate-iam-instance-profile \
    --instance-id i-xxxxxxxxx \
    --iam-instance-profile Name=$INSTANCE_PROFILE_NAME
```

### Via AWS Console

1. **Go to EC2 Console**
2. **Select your Prometheus instance**
3. **Actions** → **Security** → **Modify IAM Role**
4. **Select**: `PrometheusEC2DiscoveryInstanceProfile`
5. **Update IAM Role**

## Verification

After attaching the role, verify it's working:

```bash
# SSH into your Prometheus instance
ssh -i your-key.pem ubuntu@your-prometheus-ip

# Test AWS permissions
aws sts get-caller-identity
aws ec2 describe-regions --region us-east-1
```

## Security Considerations

- **Least Privilege**: Role only grants necessary EC2 discovery permissions
- **Regional Scope**: Primary permissions limited to deployment region
- **No Write Access**: Read-only permissions for EC2 metadata
- **Condition-Based**: Includes conditions to limit scope where possible


## Cost Impact
This template creates IAM resources only - **no additional AWS charges**. 

## Support
For issues with:
- **Template deployment**: Check CloudFormation events and logs
- **Prometheus configuration**: Refer to AWS Marketplace listing documentation
- **EC2 permissions**: Review CloudTrail for access denials
