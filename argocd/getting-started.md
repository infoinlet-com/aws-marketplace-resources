# ArgoCD for Kubernetes Deployment — Getting Started Guide

This guide walks you through subscribing to the **ArgoCD for Kubernetes Deployment** AMI on AWS Marketplace, launching your instance, accessing the ArgoCD web UI, and connecting your first Kubernetes cluster for GitOps-based deployments.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Step 1 — Subscribe on AWS Marketplace](#step-1--subscribe-on-aws-marketplace)
4. [Step 2 — Launch the EC2 Instance](#step-2--launch-the-ec2-instance)
5. [Step 3 — Configure Security Group](#step-3--configure-security-group)
6. [Step 4 — Access the ArgoCD Web UI](#step-4--access-the-argocd-web-ui)
7. [Step 5 — Retrieve the Admin Password](#step-5--retrieve-the-admin-password)
8. [Step 6 — Log In to ArgoCD](#step-6--log-in-to-argocd)
9. [Step 7 — Connect a Git Repository](#step-7--connect-a-git-repository)
10. [Step 8 — Connect a Kubernetes Cluster](#step-8--connect-a-kubernetes-cluster)
11. [Step 9 — Create and Deploy Your First Application](#step-9--create-and-deploy-your-first-application)
12. [Troubleshooting](#troubleshooting)
13. [Support](#support)

---

## Overview

This AMI provides a fully pre-installed and hardened **ArgoCD v3.3.6** server running on **K3s Kubernetes** and **Ubuntu 24.04 LTS**. ArgoCD is a declarative GitOps continuous delivery tool for Kubernetes.

Once launched, this EC2 instance acts as a **GitOps hub** — it reads application manifests from your Git repository and continuously deploys them to any connected Kubernetes cluster, including:

- Amazon EKS
- On-premises or self-managed Kubernetes clusters
- Local clusters (e.g., Docker Desktop, Kind, Minikube)
- Any CNCF-conformant Kubernetes environment

No manual installation or configuration is required. The instance is ready to use within a few minutes of launch.

---

## Prerequisites

Before you begin, ensure you have:

- An active AWS account
- Permission to launch EC2 instances and configure security groups
- An SSH key pair created in the target AWS region
- A Git repository (GitHub, GitLab, Bitbucket, or self-hosted) containing Kubernetes manifests
- (Optional) `kubectl` installed on your local machine for cluster management
- (Optional) `argocd` CLI installed for advanced configuration

---

## Step 1 — Subscribe on AWS Marketplace

1. Navigate to the **ArgoCD for Kubernetes Deployment** listing on [AWS Marketplace](https://aws.amazon.com/marketplace).
2. Click **Continue to Subscribe**.
3. Review the terms and pricing, then click **Accept Terms**.
4. Wait for the subscription to be confirmed (this may take a few minutes).
5. Once confirmed, click **Continue to Configuration**.

---

## Step 2 — Launch the EC2 Instance

1. On the **Configure this software** page, select:
   - **Fulfillment option**: Amazon Machine Image (AMI)
   - **Software version**: latest available
   - **Region**: your preferred AWS region
2. Click **Continue to Launch**.
3. On the **Launch this software** page, select **Launch through EC2**.
4. Click **Launch** — this opens the EC2 launch wizard with the AMI pre-selected.
5. Configure the instance:
   - **Instance type**: `t3.medium` (minimum recommended) or larger for production workloads
   - **Key pair**: select an existing key pair or create a new one — you will need this to SSH into the instance
   - **Network settings**: select your VPC and subnet
6. Click **Launch Instance**.
7. Note the **Public IPv4 address** or **Public IPv4 DNS** from the instance details page — you will use this to access the ArgoCD UI.

---

## Step 3 — Configure Security Group

The ArgoCD web UI is accessible on port **30080**. You must allow inbound traffic on this port.

1. In the EC2 console, navigate to your instance → **Security** tab → click the security group name.
2. Click **Edit inbound rules** → **Add rule**:

   | Type       | Protocol | Port Range | Source              |
   |------------|----------|------------|---------------------|
   | Custom TCP | TCP      | 30080      | Your IP or 0.0.0.0/0 |
   | SSH        | TCP      | 22         | Your IP             |

3. Click **Save rules**.

> **Security note**: Restricting port 30080 to your IP address is recommended for production use. Allowing `0.0.0.0/0` exposes the UI to the public internet.

---

## Step 4 — Access the ArgoCD Web UI

Once the instance is running and the security group is configured, open your browser and navigate to:

```
http://<your-ec2-public-dns>:30080
```

For example:
```
http://ec2-54-174-124-226.compute-1.amazonaws.com:30080
```

You can find your public DNS in the EC2 console under **Instance summary** → **Public IPv4 DNS**.

> The instance may take **2-3 minutes** after launch before ArgoCD is fully ready. If the page does not load immediately, wait a moment and refresh.

---

## Step 5 — Retrieve the Admin Password

The initial ArgoCD admin password is auto-generated and stored as a Kubernetes secret inside the instance. You must SSH into the instance to retrieve it.

**Connect via SSH:**

```bash
ssh -i /path/to/your-key.pem ubuntu@<your-ec2-public-dns>
```

For example:
```bash
ssh -i ~/Downloads/my-key.pem ubuntu@ec2-54-174-124-226.compute-1.amazonaws.com
```

**Retrieve the admin password:**

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Copy the output — this is your initial admin password.

> **Important**: Change this password immediately after your first login. See [Step 6](#step-6--log-in-to-argocd) for instructions.

---

## Step 6 — Log In to ArgoCD

1. Open the ArgoCD UI in your browser:
   ```
   http://<your-ec2-public-dns>:30080
   ```
2. Enter the credentials:
   - **Username**: `admin`
   - **Password**: the password retrieved in Step 5
3. Click **Sign In**.

**Change the admin password (recommended):**

After logging in, go to **User Info** (top-left menu) → **Update Password**, or run via CLI:

```bash
argocd account update-password \
  --account admin \
  --current-password <retrieved-password> \
  --new-password <your-new-password> \
  --server <your-ec2-public-dns>:30080 \
  --insecure
```

---

## Step 7 — Connect a Git Repository

ArgoCD needs access to your Git repository to read application manifests.

### Via the Web UI

1. Go to **Settings** → **Repositories** → **Connect Repo**.
2. Select connection method:
   - **HTTPS** (recommended): enter your repository URL and credentials
   - **SSH**: paste your private key (without passphrase)
3. Fill in the details:
   - **Repository URL**: `https://github.com/your-org/your-repo`
   - **Username**: your Git username
   - **Password**: your Git personal access token (PAT)
4. Click **Connect** — a green checkmark confirms successful connection.

### Via SSH (CLI on the instance)

```bash
argocd repo add https://github.com/your-org/your-repo \
  --username your-username \
  --password your-github-pat \
  --server <your-ec2-public-dns>:30080 \
  --insecure
```

> **GitHub PAT**: Create one at GitHub → Settings → Developer settings → Personal access tokens → select `repo` scope.

---

## Step 8 — Connect a Kubernetes Cluster

By default, ArgoCD can deploy to the **local K3s cluster** (the EC2 instance itself, referred to as `in-cluster`). To deploy to external clusters such as EKS, follow the steps below.

### Connect an Amazon EKS Cluster

1. On your local machine, ensure `kubectl` is configured for your EKS cluster:
   ```bash
   aws eks update-kubeconfig --region <region> --name <cluster-name>
   ```

2. Install the `argocd` CLI:
   ```bash
   brew install argocd          # macOS
   # or
   curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
   chmod +x argocd && sudo mv argocd /usr/local/bin/
   ```

3. Log in to your ArgoCD instance:
   ```bash
   argocd login <your-ec2-public-dns>:30080 --insecure --username admin
   ```

4. Add the EKS cluster:
   ```bash
   argocd cluster add <eks-context-name> \
     --server <your-ec2-public-dns>:30080 \
     --insecure
   ```
   Replace `<eks-context-name>` with the context name from `kubectl config get-contexts`.

5. Verify the cluster was added:
   ```bash
   argocd cluster list --server <your-ec2-public-dns>:30080 --insecure
   ```

### Verify in the Web UI

Go to **Settings** → **Clusters** — your connected cluster should appear with a green status indicator.

---

## Step 9 — Create and Deploy Your First Application

### Via the Web UI

1. Click **New App** (or **+ New Application**).
2. Fill in the **General** section:
   - **Application Name**: `my-app`
   - **Project**: `default`
   - **Sync Policy**: `Automatic` (recommended for GitOps)
   - Enable **Prune Resources** and **Self Heal**
3. Fill in the **Source** section:
   - **Repository URL**: select your connected repository
   - **Revision**: `HEAD`
   - **Path**: path to your Kubernetes manifests (e.g., `k8s/` or `manifests/`)
4. Fill in the **Destination** section:
   - **Cluster**: select your target cluster
   - **Namespace**: your target namespace (e.g., `my-app`)
5. Enable **Create Namespace** under Sync Options.
6. Click **Create**.

ArgoCD will immediately sync and deploy your application. You can monitor the deployment status in the application dashboard.

### Via a Manifest File

Create an `Application` manifest and apply it to the ArgoCD cluster:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/your-repo
    targetRevision: HEAD
    path: k8s/
  destination:
    name: <cluster-name>
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Apply it on the EC2 instance:
```bash
kubectl apply -f application.yaml
```

---

## Troubleshooting

### ArgoCD UI not loading on port 30080

- Confirm the instance is in **Running** state and has passed status checks.
- Verify port 30080 is open in the security group inbound rules.
- Wait 2-3 minutes after launch for K3s and ArgoCD to fully initialize.
- SSH into the instance and check pod status:
  ```bash
  kubectl get pods -n argocd
  ```
  All pods should show `Running` or `Completed`.

### Cannot retrieve admin password

- Ensure you are SSH'd into the instance as `ubuntu`.
- Confirm `kubectl` is available:
  ```bash
  kubectl version --client
  ```
- If the secret does not exist, ArgoCD may still be initializing. Wait a moment and retry.

### Repository connection fails

- Ensure your GitHub PAT has `repo` scope.
- For HTTPS connections, use a PAT instead of your account password (GitHub no longer accepts passwords for Git operations).
- Verify the repository URL is correct and accessible.

### Cluster connection fails

- Ensure the EKS cluster API endpoint is publicly accessible, or that the EC2 instance is in the same VPC.
- Confirm your `kubeconfig` context is correct: `kubectl config get-contexts`.
- Check that the ArgoCD service account has sufficient RBAC permissions on the target cluster.

### Application stuck in OutOfSync

- Click **Sync** in the UI to trigger a manual sync.
- Check the application details for specific error messages under **Conditions**.
- Verify your Git repository path contains valid Kubernetes manifests.

---

## Support

- **Technical Issues**: Open an issue in the [aws-ami-resources](https://github.com/infoinlet/aws-ami-resources) GitHub repository.
- **AWS Marketplace questions**: Use the AWS Marketplace support channel on the listing page.
- **ReadMe on instance**: A quick-reference guide is also available after SSH at `/home/ubuntu/README.md`.
