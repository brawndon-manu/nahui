# Architecture

> This is the per-component detail behind the design. The canonical diagram
> lives in the [README](../README.md#architecture); here I break down what each
> piece does and why I built it that way.

## Components

| Component | Path | Pillar | Phase |
|---|---|---|---|
| Baseline app | `cmd/nahui-app`, `internal/server` | (the artifact) | 1 |
| Container build | `Dockerfile` | — | 1 |
| CI pipeline | `.github/workflows/ci.yml` | all | 1→4 |
| SBOM + scan | `make sbom`, `make scan` | 1 (SBOM) | 2 |
| Signing + attest | `make sign`, `make attest` | 2, 3 | 3→4 |
| Admission policy | `policies/verify-images.yaml` | 4 (enforce) | 5 |
| Deploy manifests | `deploy/` | — | 5 |

## Flow

Here's the path an artifact takes from my keyboard to a running pod:

1. **Build** — `nahui-app` compiles to a static binary, packaged into a
   distroless image with the build version baked in via `-ldflags`.
2. **Describe** — Syft generates SPDX + CycloneDX SBOMs from the image.
3. **Scan** — Grype gates the build, failing on critical CVEs.
4. **Sign** — cosign keyless-signs the image and the entry lands in Rekor.
5. **Attest** — SLSA provenance and the SBOM get attached as signed
   attestations, bound to the image digest.
6. **Enforce** — at admission, Kyverno verifies the signature, provenance,
   SBOM, and digest-pinning before the pod is allowed to schedule.

## Design choices

- **Go + distroless** — a static binary keeps the SBOM and attack surface as
  small as possible, so what I'm attesting to is my code, not a base image full
  of packages.
- **Keyless (OIDC) signing** — no long-lived keys to manage or leak; signing
  runs against the CI's OIDC identity instead.
- **Digest pinning enforced at admission** — mutable tags are a policy failure,
  not just a convention. If it isn't pinned by digest, it doesn't run.
