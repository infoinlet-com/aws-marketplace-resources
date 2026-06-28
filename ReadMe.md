# AWS Marketplace Resources

Supplementary resources, guides, scripts, and templates for our **AWS Marketplace
products**. These materials help subscribers deploy and operate our offerings in
their own AWS accounts.

The repository covers two delivery types:

- **AMI products** - machine images launched on Amazon EC2.
- **MCP server products** - containers hosted on Amazon Bedrock AgentCore Runtime,
  listed under the AWS Marketplace "AI Agents and Tools" category.

---

## Repository structure

```
aws-marketplace-resources/
├── ami/                                  # AMI-based Marketplace products
│   ├── argocd/                           # ArgoCD for Kubernetes Deployment
│   │   └── getting-started.md
│   └── prometheus-grafana/               # Prometheus & Grafana Monitoring
│       ├── ReadMe.md
│       ├── cloudformation/               # IAM / setup templates
│       │   ├── iam_role_policy_setup.yaml
│       │   └── usage.md
│       └── scripts/                      # Installation / setup scripts
│           └── install_node_exporter.sh
└── mcp/                                  # MCP server Marketplace products
    └── container/                        # Container delivery on Bedrock AgentCore Runtime
        └── agentcore_runtime.md          # Universal Data Format Converter - usage guide
```

---

## Products

### MCP server products (container on Amazon Bedrock AgentCore Runtime)

| Product | Description | Resources |
|---|---|---|
| Universal Data Format Converter | MCP server that converts and inspects CSV, TSV, JSON, NDJSON, YAML, XML, Excel, Parquet, and Avro, with format auto-detection and schema inference. | [Usage guide](mcp/container/agentcore_runtime.md) |

### AMI products (Amazon EC2)

| Product | Description | Resources |
|---|---|---|
| Prometheus & Grafana Monitoring | Production-ready monitoring stack with EC2 auto-discovery, prebuilt Grafana dashboards, IAM CloudFormation, and Node Exporter setup. | [Guide](ami/prometheus-grafana/ReadMe.md) |
| ArgoCD for Kubernetes Deployment | GitOps continuous-delivery server for Kubernetes. | [Getting started](ami/argocd/getting-started.md) |

---

## Prerequisites

- An active subscription to the corresponding product in AWS Marketplace.
- AWS CLI v2 installed and configured.
- Appropriate AWS permissions for the resources you create (EC2/IAM for AMI
  products; IAM and Amazon Bedrock AgentCore for MCP products).

---

## Getting started

1. Clone this repository:
   ```bash
   git clone https://github.com/infoinlet-com/aws-marketplace-resources.git
   cd aws-marketplace-resources
   ```
2. Open the guide for your product:
   - MCP server (AgentCore): [`mcp/container/agentcore_runtime.md`](mcp/container/agentcore_runtime.md)
   - Prometheus & Grafana AMI: [`ami/prometheus-grafana/ReadMe.md`](ami/prometheus-grafana/ReadMe.md)
   - ArgoCD AMI: [`ami/argocd/getting-started.md`](ami/argocd/getting-started.md)
3. Follow that guide for deployment and configuration.

---

## Support

- Product-specific questions and entitlement issues: use the **Support** link on
  the product's AWS Marketplace listing page.
- Problems with the materials in this repository: open a GitHub issue.

When reporting an issue, never include credentials, access keys, or other
sensitive information.

---

## Notes

- Scripts and templates are provided as-is; review them before running in
  production.
- AWS Marketplace listing pages are the authoritative source for each product's
  current features, pricing, and requirements.
