# Stand up the full Phase-5 demo environment in one command:
#   kind cluster -> Kyverno -> nahui namespace -> verify-images policy.
#
# After this runs, deploy the demo with:
#   kubectl apply -f deploy/verified.yaml    # signed image -> admitted
#   kubectl apply -f deploy/unsigned.yaml    # untrusted nginx -> denied
#
# Tear it all down with scripts/cluster-down.ps1.

param(
  [string]$ClusterName = "nahui",
  # Pinned to a cgroup-v1-compatible node image. The default kind image (newer
  # k8s) needs cgroup v2, which some WSL2 setups don't expose. v1.31.6 runs on
  # both, and the k8s version does not matter for the admission demo.
  [string]$NodeImage   = "kindest/node:v1.31.6"
)

$ErrorActionPreference = "Stop"

function Require-Cmd($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "$name not found on PATH. Install it first (see Docs / README)."
  }
}

Require-Cmd kind
Require-Cmd kubectl

# Docker engine must be running - kind runs the cluster as containers.
docker info *> $null
if ($LASTEXITCODE -ne 0) {
  throw "Docker engine isn't reachable. Start Docker Desktop and wait for 'Engine running'."
}

# 1. Cluster (idempotent - skip if it already exists).
if ((kind get clusters 2>$null) -contains $ClusterName) {
  Write-Host "Cluster '$ClusterName' already exists - skipping create."
} else {
  Write-Host "Creating kind cluster '$ClusterName' ($NodeImage)..."
  kind create cluster --name $ClusterName --image $NodeImage
}
kubectl wait --for=condition=Ready "node/$ClusterName-control-plane" --timeout=120s

# 2. Kyverno (server-side apply - its CRDs are large).
Write-Host "Installing Kyverno..."
kubectl apply --server-side -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
kubectl wait --for=condition=Available deployment/kyverno-admission-controller -n kyverno --timeout=180s

# 3. Namespace + policy.
Write-Host "Applying namespace and verify-images policy..."
kubectl apply -f deploy/namespace.yaml
kubectl apply -f policies/verify-images.yaml

Write-Host ""
Write-Host "Demo environment ready. Try it:" -ForegroundColor Green
Write-Host "  kubectl apply -f deploy/verified.yaml    # signed -> admitted"
Write-Host "  kubectl apply -f deploy/unsigned.yaml    # nginx  -> denied"
Write-Host "Tear down with: scripts/cluster-down.ps1"
