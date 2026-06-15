# Tear down the Phase-5 demo cluster. Nothing is lost - everything that defines
# the demo lives in deploy/ and policies/, so scripts/cluster-up.ps1 rebuilds it.

param(
  [string]$ClusterName = "nahui"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
  throw "kind not found on PATH."
}

Write-Host "Deleting kind cluster '$ClusterName'..."
kind delete cluster --name $ClusterName
Write-Host "Done."
