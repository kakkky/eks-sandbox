## kind Cluster Operations
At development environment, we use [kind](https://kind.sigs.k8s.io/) to create a local Kubernetes cluster.

### Create Cluster
This creates a kind cluster named `sandbox` using the configuration file located at `./k8s/clusters/kind/config.yaml` with Kubernetes version v1.29.0.

```sh
kind create cluster --name sandbox --config ./k8s/cluster/kind/config.yaml --image kindest/node:v1.29.0
```
The following are created:
- A control-plane node
- A worker node (with extra port mappings for NodePort: 30080)
- `kind-sandbox` context (set in kubeconfig)

### Delete Cluster

```sh
kind delete cluster --name sandbox
```

### List Clusters

```sh
kind get clusters
```

### Load Local Docker Image

Load locally built images into the kind cluster:

```sh
# Build with timestamp tag
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
docker build -t app:$TIMESTAMP .

# Load into kind cluster
kind load docker-image app:$TIMESTAMP --name sandbox
```

## Deploy Operations 

### helmfile apply
This command deploys it to the kind cluster using helmfile:
```sh
cd ./k8s
helmfile -e development apply
```
You must set environment: `development`, therefore kubectl access the kind cluster by referring `kind-sandbox` context.

### Setting kubeconfig context
You can use kubectl commands to interact with the kind cluster, by setting below.

To access the kind cluster, set the kubeconfig context to `kind-sandbox`:
```sh
kubectl config use-context kind-sandbox
```

Check your current-context:
```sh
kubectl config current-context
```


### Local Access
Access NodePort services via `localhost:8080`:
```sh
curl http://localhost:8080
```


