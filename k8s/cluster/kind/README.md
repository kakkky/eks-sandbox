## kind Cluster Operations
At development environment, we use [kind](https://kind.sigs.k8s.io/) to create a local Kubernetes cluster.

## Prerequisites

### Create Cluster
Create a kind cluster named `sandbox` using the configuration file with Kubernetes version v1.29.0:

```sh
kind create cluster --name sandbox --config ./k8s/cluster/kind/config.yaml --image kindest/node:v1.29.0
```

This creates:
- A control-plane node
- A worker node (with extra port mappings for NodePort: 30080)
- `kind-sandbox` context (automatically set in kubeconfig)

### Setting kubeconfig context
To access the kind cluster, set the kubeconfig context to `kind-sandbox`:

```sh
kubectl config use-context kind-sandbox
```

Check your current context:
```sh
kubectl config current-context
```

## Deploy Operations

### 1. Build and Load Docker Image

When application code changes, rebuild and load the image into kind:

```sh
# Build with timestamp tag
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
docker build -t app:$TIMESTAMP .

# Load into kind cluster
kind load docker-image app:$TIMESTAMP --name sandbox
```

### 2. Update Helm Values

Update the image tag in `/k8s/values/development/values.yaml`:

```yaml
deployment:
  image:
    repository: app
    tag: "<TIMESTAMP>"
```

### 3. Deploy with Helmfile

Deploy the application to kind cluster using helmfile:

```sh
cd ./k8s
helmfile -e development apply
```

You must set environment: `development`, therefore helmfile uses the `kind-sandbox` context to access the kind cluster.

### helmfile destroy

To destroy the deployed resources in the kind cluster:

```sh
cd ./k8s
helmfile -e development destroy
```

## Verify Deployment

### Check Resources

```sh
# Check deployments
kubectl get deployments -n app-development

# Check pods
kubectl get pods -n app-development

# Check services
kubectl get services -n app-development

# Check pod logs
kubectl logs -n app-development -l app=app-http-server --all-containers=true
```

### Access Application

Access NodePort services via `localhost:8080`:

```sh
curl http://localhost:8080
```

## Cluster Management

### Delete Cluster

```sh
kind delete cluster --name sandbox
```

### List Clusters

```sh
kind get clusters
```

## Cleanup

To completely clean up the development environment:

```sh
# Destroy Kubernetes resources
cd k8s
helmfile -e development destroy

# Delete kind cluster
kind delete cluster --name sandbox
```


