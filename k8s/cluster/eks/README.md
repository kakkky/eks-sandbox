## EKS Cluster Operations
At production environment, we use [Amazon EKS](https://aws.amazon.com/eks/) to run a managed Kubernetes cluster.

## Prerequisites

### Terraform Infrastructure
Before deploying to EKS, ensure the infrastructure is provisioned:

```sh
cd terraform
terraform init
terraform plan
terraform apply
```

This creates:
- VPC with public/private subnets
- EKS cluster (`eks-sandbox`)
- EKS Node Group with t3.nano instances
- Application Load Balancer (ALB)
- ECR repository
- IAM roles and policies
- Route53 hosted zone
- ACM certificate

### Verify Infrastructure

After Terraform applies, verify that all resources are created successfully:

```sh
# Check EKS cluster
aws eks describe-cluster --name eks-sandbox --query 'cluster.status' --output text

# Check Node Group
aws eks describe-nodegroup --cluster-name eks-sandbox --nodegroup-name eks-sandbox-node-group --query 'nodegroup.status' --output text

# Check ECR repository
aws ecr describe-repositories --repository-names eks-sandbox-ecr-repository --query 'repositories[0].repositoryUri' --output text

# Check ALB
aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`eks-sandbox-alb`].[LoadBalancerName,State.Code,DNSName]' --output table

# Check Route53 hosted zone
aws route53 list-hosted-zones --query 'HostedZones[?Name==`eks-sandbox.com.`].[Name,Id]' --output table

# Check ACM certificate
aws acm list-certificates --query 'CertificateSummaryList[?DomainName==`eks-sandbox.com`].[DomainName,Status]' --output table
```

Expected statuses:
- EKS cluster: `ACTIVE`
- Node Group: `ACTIVE`
- ALB: `active`
- ACM certificate: `ISSUED` (may take some time for DNS validation)

### Assume Developer Role

Before accessing EKS cluster, assume the `developer-role` that has necessary permissions.

#### Setup AWS Profile (One-time setup)

Add the following to `~/.aws/config`:

```ini
[profile developer]
role_arn = arn:aws:iam::<YOUR_ACCOUNT_ID>:role/developer-role
source_profile = default
```

You can get the role ARN:
```sh
# Get role ARN
aws iam get-role --role-name developer-role --query 'Role.Arn' --output text
```

#### Use the Profile

```sh
export AWS_PROFILE=developer
```

Verify:
```sh
aws sts get-caller-identity
# Should show: "Arn": "...assumed-role/developer-role/..."
```

### Configure kubectl
After assuming the developer role, configure kubectl to access the EKS cluster:

```sh
aws eks update-kubeconfig --region ap-northeast-1 --name eks-sandbox
```

This creates the `eks-sandbox` context in your kubeconfig.

### Setting kubeconfig context
To access the EKS cluster, set the kubeconfig context to `eks-sandbox`:

```sh
kubectl config use-context eks-sandbox
```

Check your current context:
```sh
kubectl config current-context
```

## Deploy Operations

### 1. Build and Push Docker Image to ECR

When application code changes, rebuild and push the image to ECR:

```sh
# Build with timestamp tag
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
docker build -t app:$TIMESTAMP .

# Get ECR repository URI
ECR_REPO_URI=$(aws ecr describe-repositories --repository-names eks-sandbox-ecr-repository --query 'repositories[0].repositoryUri' --output text)

# Tag image for ECR
docker tag app:$TIMESTAMP $ECR_REPO_URI:$TIMESTAMP

# Login to ECR
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $ECR_REPO_URI

# Push image to ECR
docker push $ECR_REPO_URI:$TIMESTAMP
```

### 2. Update Helm Values

Update the image tag in `/k8s/values/production/values.yaml`:

```yaml
deployment:
  image:
    repository: <ECR_REPO_URI>
    tag: "<TIMESTAMP>"
```

### 3. Deploy with Helmfile

Deploy the application to EKS using helmfile:

```sh
cd ./k8s
helmfile -e production apply
```

You must set environment: `production`, therefore helmfile uses the `eks-sandbox` context to access the EKS cluster.

### helmfile destroy

To destroy the deployed resources in the EKS cluster:

```sh
cd ./k8s
helmfile -e production destroy
```

## Verify Deployment

### Check Resources

```sh
# Check deployments
kubectl get deployments -n app-production

# Check pods
kubectl get pods -n app-production

# Check services
kubectl get services -n app-production

# Check pod logs
kubectl logs -n app-production -l app=app-http-server --all-containers=true
```

### Access Application

Access the application via the ALB DNS name or Route53 domain:

```sh
# Get ALB DNS name
aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`eks-sandbox-alb`].DNSName' --output text

# Or use Route53 domain (if DNS is configured)
curl https://app.eks-sandbox.com
```

## Infrastructure Updates

If you make changes to Terraform configuration:

```sh
cd terraform
terraform plan
terraform apply
```

After infrastructure changes, you may need to re-deploy the application:

```sh
cd k8s
helmfile -e production apply
```

## Cleanup

To completely tear down the EKS environment:

1. First, destroy Kubernetes resources:
```sh
cd k8s
helmfile -e production destroy
```

2. Then, destroy Terraform infrastructure:
```sh
cd terraform
terraform destroy
```

**Note**: Make sure to destroy Kubernetes resources first to avoid orphaned AWS resources (like LoadBalancers) that Terraform doesn't track.
