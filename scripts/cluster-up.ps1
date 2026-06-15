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
  # Empty = use kind's default (current) node image. Only override if your
  # WSL2/Docker is stuck on cgroup v1, which the current image can't run on:
  #   .\scripts\cluster-up.ps1 -NodeImage kindest/node:v1.31.6
  # (The proper fix is cgroup v2 - see Docs-Internal / README.)
  [string]$NodeImage   = ""
)

# NB: do NOT set $ErrorActionPreference = 'Stop' here. kind and kubectl write
# benign progress/info to stderr (e.g. "No kind clusters found."), which Stop
# would turn into fatal errors. We check $LASTEXITCODE explicitly instead.

function Require-Cmd($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    Write-Error "$name not found on PATH. Install it first (see Docs / README)."
    exit 1
  }
}

function Die($msg) { Write-Error $msg; exit 1 }

Require-Cmd kind
Require-Cmd kubectl

# Docker engine must be running - kind runs the cluster as containers.
docker info *> $null
if ($LASTEXITCODE -ne 0) {
  Die "Docker engine isn't reachable. Start Docker Desktop and wait for 'Engine running'."
}

# 1. Cluster (idempotent). kind prints "No kind clusters found." to stderr when
#    empty, so merge stderr and just scan the text for our cluster name.
$existing = (kind get clusters 2>&1 | Out-String)
$haveCluster = ($existing -split "`n" | ForEach-Object { $_.Trim() }) -contains $ClusterName

if ($haveCluster) {
  Write-Host "Cluster '$ClusterName' already exists - skipping create."
} elseif ($NodeImage) {
  Write-Host "Creating kind cluster '$ClusterName' ($NodeImage)..."
  kind create cluster --name $ClusterName --image $NodeImage
  if ($LASTEXITCODE -ne 0) { Die "kind create cluster failed." }
} else {
  Write-Host "Creating kind cluster '$ClusterName' (kind default image)..."
  kind create cluster --name $ClusterName
  if ($LASTEXITCODE -ne 0) { Die "kind create cluster failed." }
}

kubectl wait --for=condition=Ready "node/$ClusterName-control-plane" --timeout=120s

# 2. Kyverno (server-side apply - its CRDs are large).
Write-Host "Installing Kyverno..."
kubectl apply --server-side -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
if ($LASTEXITCODE -ne 0) { Die "Kyverno install failed." }
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
