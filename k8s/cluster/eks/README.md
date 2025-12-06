## EKS Cluster Operations
At production environment, we use [Amazon EKS](https://aws.amazon.com/eks/) to run a managed Kubernetes cluster.

## Prerequisites

### Edit file to assume developer role
To specify which IAM users can assume the `developer_role` in Terraform, edit the variable `identifiers` in your configuration and set the default value to your own IAM user ARN.

Example:
```hcl
// terraform/main.tf
data "aws_iam_policy_document" "developer_assume_role_policy" {
  statement {
    sid    = "AllowAssumeRoleForDeveloper"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::<YOUR_ACCOUNT_ID>:user/<YOUR_USER_NAME>"]
    }
    actions = ["sts:AssumeRole"]
  }
}
```

Assuming the `developer_role` allows you to run `terraform apply` and perform `kubectl` operations on the EKS cluster.

If you want to allow multiple users, add their ARNs to the array.

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
- EKS Node Group with t3.micro instances
- Application Load Balancer (ALB) - HTTP only
- ECR repository with VPC endpoints
- IAM roles and policies

### Add Assume Role Settings to AWS Provider
To allow Terraform to assume the `developer_role`, uncomment the `assume_role` block in `terraform/provider.tf`:
```hcl
provider "aws" {
  region  = "ap-northeast-1"
  profile = "default"
  assume_role {
    role_arn = aws_iam_role.developer_role.arn
  }
}
```

And run:
```sh
terraform apply
```

### Verify Infrastructure

After Terraform applies, verify that all resources are created successfully:

```sh
# Check EKS cluster
aws eks describe-cluster --name eks-sandbox --query 'cluster.[name,status,version,endpoint,resourcesVpcConfig.vpcId]' --output table

# Check Node Group
aws eks describe-nodegroup --cluster-name eks-sandbox --nodegroup-name eks-sandbox-node-group --query 'nodegroup.[nodegroupName,status,instanceTypes,desiredSize,minSize,maxSize,subnets]' --output table

# Check EC2 instances
aws ec2 describe-instances --filters "Name=tag:eks:nodegroup-name,Values=eks-sandbox-node-group" --query 'Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress,SecurityGroups[].GroupId]' --output table

# Check ECR repository
aws ecr describe-repositories --repository-names eks-sandbox-ecr-repository --query 'repositories[0].[repositoryName,repositoryUri,createdAt]' --output table

# Check ALB
aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`eks-sandbox-alb`].[LoadBalancerName,State.Code,DNSName,VpcId,SecurityGroups,Scheme]' --output table

# Check ALB Target Group
aws elbv2 describe-target-groups --query 'TargetGroups[?TargetGroupName==`eks-sandbox-alb-tg`].[TargetGroupName,Port,Protocol,HealthCheckPath,VpcId]' --output table

# Check VPC Endpoints
aws ec2 describe-vpc-endpoints --filters "Name=tag:Name,Values=eks-sandbox-ecr-*" --query 'VpcEndpoints[*].[VpcEndpointId,ServiceName,State]' --output table

# Check Security Groups
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=alb-sg" --query 'SecurityGroups[*].[GroupName,GroupId,Description]' --output table
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=eks-sandbox-node*" --query 'SecurityGroups[*].[GroupName,GroupId,Description]' --output table
```

Expected statuses:
- EKS cluster: `ACTIVE`
- Node Group: `ACTIVE`
- ALB: `active`
- VPC Endpoints: `available`
- Security Groups: Should show ALB SG, Node Group SG, and VPC Endpoint SG

### Configure kubectl
Configure kubectl to access the EKS cluster:

```sh
aws eks update-kubeconfig --region ap-northeast-1 --name eks-sandbox --alias eks-sandbox
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

Access the application via the ALB DNS name:

```sh
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`eks-sandbox-alb`].DNSName' --output text)

# Access via HTTP
curl http://$ALB_DNS

# Or directly
curl http://eks-sandbox-alb-xxxxxxxxx.ap-northeast-1.elb.amazonaws.com
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

