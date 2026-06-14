# Threat Model

> This maps each pillar to the attack class it defeats and the residual risk I'm
> knowingly leaving on the table. It'll grow as the implementation lands.

## Scope

The thing being defended is the path from source commit to running workload:
build, SBOM, scan, sign, provenance, attestation, and admission-time
enforcement. Out of scope (on purpose): application-layer vulnerabilities at
runtime — that's what the Falco stretch goal is for — and a compromise of my own
dev machine.

## Trust boundaries

```
[ developer ] --commit--> [ CI runner ] --image+att--> [ registry ] --pull--> [ cluster admission ] --> [ runtime ]
             ^ signed                  ^ provenance               ^ digest                ^ policy verify
```

| Boundary | What crosses it | Control |
|---|---|---|
| Dev → CI | source commit | signed commits (stretch) |
| CI → registry | image + attestations | cosign signing, SLSA provenance |
| Registry → cluster | image by digest | admission policy verification |

## Pillars → attacks (see README for the summary table)

| Pillar | Attack class it defeats | Residual risk |
|---|---|---|
| SBOM (Syft/Grype) | unknown / vulnerable deps (Log4Shell) | scanner data lag; build-time zero-days |
| Signing (cosign/Rekor) | image substitution, registry tampering | signing-identity compromise; trust-root mgmt |
| Provenance (SLSA) | build-system tampering (SolarWinds) | trust in CI isolation |
| Enforcement (Kyverno) | running unsigned/`:latest` images | policy misconfig; cluster RBAC |

## Assumptions

Worth calling out, because each one is a place the model could break down:

- The CI platform's OIDC identity is the root of build trust.
- Rekor's transparency log is available and trustworthy.
- Cluster RBAC stops anyone from bypassing the admission webhook.

## Open questions

Still on my list to work out:

- Key/identity rotation.
- VEX handling to suppress non-exploitable CVE noise (stretch).
- Build-time secret management with Vault (stretch).
