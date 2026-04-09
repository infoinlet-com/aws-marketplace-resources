# Getting Started with ArgoCD for Kubernetes Deployment

A step-by-step guide to subscribing, launching, and configuring your ArgoCD GitOps server on AWS Marketplace.

---

## Step 1 - Subscribe on AWS Marketplace

1. Go to [AWS Marketplace](https://aws.amazon.com/marketplace) and search for **ArgoCD for Kubernetes Deployment**
2. Click **View purchase options** and then **Subscribe**
3. Once the subscription is confirmed, click **Continue to Configuration**
4. Select your preferred AWS region, then click **Continue to Launch**

> Pricing is based on EC2 instance hours. You will not be charged until the instance is running.

---

## Step 2 - Launch the EC2 Instance

1. On the launch configuration screen, select **Launch through EC2**
2. Click **Launch** to open the EC2 launch wizard with the AMI pre-selected
3. Configure the instance:
   - **Instance type**: `t3.medium` is a good starting point for small teams; use `t3.large` or higher for production workloads
   - **Key pair**: select an existing key pair or create a new one — you will need this to SSH into the instance
4. Configure the **Security Group** with the following inbound rules:

   | Type       | Protocol | Port  | Source                  |
   |------------|----------|-------|-------------------------|
   | SSH        | TCP      | 22    | Your IP                 |
   | Custom TCP | TCP      | 30080 | Your IP or `0.0.0.0/0` |

   > Port **30080** is the ArgoCD web UI port exposed as a NodePort service on K3s. Restrict access to your IP in production environments.

5. Click **Launch Instance** and wait for the instance to reach the **Running** state

---

## Step 3 - SSH into the Instance

Once the instance is running, connect via SSH using your key pair:

```bash
ssh -i your-key.pem ubuntu@<EC2_PUBLIC_DNS>
```

For example:

```bash
ssh -i ~/Downloads/my-key.pem ubuntu@ec2-54-174-124-226.compute-1.amazonaws.com
```

Verify ArgoCD is running:

```bash
kubectl get pods -n argocd
```

All pods should show a `Running` or `Completed` status. If pods are still initializing, wait one to two minutes and retry.

---

## Step 4 - Access the ArgoCD Web UI

The ArgoCD web UI is directly accessible on port **30080** via the EC2 public DNS. No port forwarding or tunneling is required.

Open your browser and navigate to:

```
http://<EC2_PUBLIC_DNS>:30080
```

For example:

```
http://ec2-54-174-124-226.compute-1.amazonaws.com:30080
```

You can find your public DNS in the EC2 console under **Instance summary** → **Public IPv4 DNS**.

### Retrieve the Initial Admin Password

SSH into the instance and run:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### Log In

- **Username**: `admin`
- **Password**: output from the command above

> Change your admin password immediately after first login. Go to **User Info** (top-left menu) → **Update Password**.

---

## Step 5 - Connect a Git Repository

ArgoCD needs access to your Git repository to read application manifests.

### Via the Web UI

1. Go to **Settings** → **Repositories** → **Connect Repo**
2. Select **HTTPS** as the connection method
3. Fill in the details:
   - **Repository URL**: `https://github.com/your-org/your-repo`
   - **Username**: your Git username
   - **Password**: your Personal Access Token (PAT)
4. Click **Connect** — a green checkmark confirms a successful connection

### Via the ArgoCD CLI

Install the ArgoCD CLI on your local machine, log in to your ArgoCD instance, then add the repository:

```bash
argocd login <EC2_PUBLIC_DNS>:30080 --username admin --password <your-password> --insecure

argocd repo add https://github.com/your-org/your-repo \
  --username your-username \
  --password your-github-pat \
  --server <EC2_PUBLIC_DNS>:30080 \
  --insecure
```

> **GitHub Personal Access Token**: create one at GitHub → Settings → Developer settings → Personal access tokens → select the `repo` scope.

---

## Step 6 - Connect a Kubernetes Cluster

By default, ArgoCD can deploy to the **local K3s cluster** on the EC2 instance itself (referred to as `in-cluster`). To deploy to external clusters such as Amazon EKS, follow the steps below.

### Connect an Amazon EKS Cluster

On your local machine, update your kubeconfig for the EKS cluster:

```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>
```

Log in to ArgoCD:

```bash
argocd login <EC2_PUBLIC_DNS>:30080 --username admin --password <your-password> --insecure
```

Add the EKS cluster:

```bash
argocd cluster add <eks-context-name> \
  --server <EC2_PUBLIC_DNS>:30080 \
  --insecure
```

Replace `<eks-context-name>` with the context name shown in:

```bash
kubectl config get-contexts
```

Verify the cluster was added:

```bash
argocd cluster list --server <EC2_PUBLIC_DNS>:30080 --insecure
```

You can also confirm in the web UI under **Settings** → **Clusters**.

---

## Step 7 - Deploy Your First Application

### Via the Web UI

1. Click **New App** on the ArgoCD dashboard
2. Fill in the application details:
   - **Application Name**: `my-app`
   - **Project**: `default`
   - **Sync Policy**: `Automatic` — ArgoCD will auto-sync on every Git change
   - Enable **Prune Resources** and **Self Heal**
3. Fill in the **Source** section:
   - **Repository URL**: select your connected repository
   - **Revision**: `HEAD`
   - **Path**: path to your Kubernetes manifests (e.g., `k8s/`)
4. Fill in the **Destination** section:
   - **Cluster**: select your registered cluster
   - **Namespace**: your target namespace (e.g., `my-app`)
5. Enable **Create Namespace** under Sync Options
6. Click **Create**

ArgoCD will immediately pull the manifests from your repository and deploy them to the target cluster. You will see the application resource tree with live sync and health status.

### Via the ArgoCD CLI

```bash
argocd app create my-app \
  --repo https://github.com/your-org/your-repo.git \
  --path k8s/ \
  --dest-server https://<cluster-api-endpoint> \
  --dest-namespace my-app \
  --sync-policy automated \
  --auto-prune \
  --self-heal \
  --sync-option CreateNamespace=true \
  --server <EC2_PUBLIC_DNS>:30080 \
  --insecure
```

---

## Step 8 - Verify the Deployment

Check sync and health status from the UI or CLI:

```bash
argocd app get my-app --server <EC2_PUBLIC_DNS>:30080 --insecure
argocd app sync my-app --server <EC2_PUBLIC_DNS>:30080 --insecure
```

In the UI, a green **Synced** and **Healthy** status confirms your application is live and matches your Git repository. Any future Git commit will automatically trigger a re-sync.

---

## Tips for Production Use

- **Use a domain and TLS** — place an Application Load Balancer or NGINX reverse proxy in front of ArgoCD with an SSL certificate via AWS Certificate Manager (ACM)
- **Enable SSO** — ArgoCD supports OIDC, GitHub OAuth, and SAML for team-based access control
- **Use Projects** — ArgoCD Projects let you scope which repositories and clusters each team can access
- **Monitor ArgoCD** — expose ArgoCD metrics to Prometheus and Grafana (see the VM Monitoring listing on AWS Marketplace)
- **Back up your instance** — enable automated EBS snapshots for disaster recovery

---

## Support

- Open an issue in the [aws-ami-resources](https://github.com/infoinlet/aws-ami-resources) GitHub repository
- Use the AWS Marketplace support channel on the listing page
- A quick-reference guide is available on the instance at `/home/ubuntu/README.md` after SSH
