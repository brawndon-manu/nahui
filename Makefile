# Nahui — supply chain security platform
#
# Targets are grouped by pillar so this file also works as a map of the
# build -> scan -> sign -> attest -> enforce flow. A lot of them just shell out
# to syft/grype/cosign/kubectl — run `make tools` for install links, or let CI
# do it.

# --- Config ----------------------------------------------------------------
APP        := nahui-app
PKG        := ./cmd/nahui-app
REGISTRY   ?= ghcr.io/brawndon-manu
IMAGE      := $(REGISTRY)/$(APP)
VERSION    ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
IMAGE_REF  := $(IMAGE):$(VERSION)
SBOM_DIR   := sbom

# Keyless verification identity: the CI workflow's OIDC subject + issuer.
# Used by `make verify` to confirm a signature came from this repo's pipeline.
OIDC_ISSUER ?= https://token.actions.githubusercontent.com
CERT_IDENTITY_RE ?= ^https://github.com/brawndon-manu/nahui/.github/workflows/.+@.+

.DEFAULT_GOAL := help

# --- App (Phase 1) ---------------------------------------------------------
.PHONY: build
build: ## Build the app binary locally
	CGO_ENABLED=0 go build -trimpath \
		-ldflags "-s -w -X github.com/brawndon-manu/nahui/internal/server.Version=$(VERSION)" \
		-o bin/$(APP) $(PKG)

.PHONY: test
test: ## Run unit tests
	go test ./... -race -count=1

.PHONY: run
run: ## Run the app locally on :8080
	go run $(PKG)

.PHONY: docker
docker: ## Build the container image
	docker build --build-arg VERSION=$(VERSION) -t $(IMAGE_REF) .

# --- Pillar 1: SBOM (Phase 2) ----------------------------------------------
.PHONY: sbom
sbom: ## Generate SBOM (SPDX + CycloneDX) with Syft
	mkdir -p $(SBOM_DIR)
	syft $(IMAGE_REF) -o spdx-json=$(SBOM_DIR)/$(APP).spdx.json
	syft $(IMAGE_REF) -o cyclonedx-json=$(SBOM_DIR)/$(APP).cdx.json

.PHONY: scan
scan: ## Scan the image/SBOM for vulns; fail on critical (Grype)
	grype $(IMAGE_REF) --fail-on critical

# --- Pillar 2 & 3: Sign + Attest (Phases 3-4) ------------------------------
.PHONY: sign
sign: ## Keyless-sign the image with cosign (OIDC)
	COSIGN_EXPERIMENTAL=1 cosign sign --yes $(IMAGE_REF)

.PHONY: attest
attest: ## Attach the SBOM as a signed attestation
	COSIGN_EXPERIMENTAL=1 cosign attest --yes \
		--predicate $(SBOM_DIR)/$(APP).cdx.json \
		--type cyclonedx $(IMAGE_REF)

.PHONY: verify
verify: ## Verify the image signature against this repo's CI identity (keyless)
	cosign verify $(IMAGE_REF) \
		--certificate-oidc-issuer "$(OIDC_ISSUER)" \
		--certificate-identity-regexp "$(CERT_IDENTITY_RE)"
	# TODO(Phase 4): also verify the SLSA provenance + SBOM attestations:
	#   cosign verify-attestation --type slsaprovenance $(IMAGE_REF) ...

# --- Pillar 4: Enforce (Phase 5) -------------------------------------------
KIND_CLUSTER ?= nahui
KIND_NODE_IMAGE ?= kindest/node:v1.31.6

.PHONY: cluster-up
cluster-up: ## Create kind cluster + install Kyverno + apply namespace & policy
	kind create cluster --name $(KIND_CLUSTER) --image $(KIND_NODE_IMAGE)
	kubectl wait --for=condition=Ready node/$(KIND_CLUSTER)-control-plane --timeout=120s
	kubectl apply --server-side -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml
	kubectl wait --for=condition=Available deployment/kyverno-admission-controller -n kyverno --timeout=180s
	kubectl apply -f deploy/namespace.yaml
	kubectl apply -f policies/verify-images.yaml

.PHONY: cluster-down
cluster-down: ## Delete the kind cluster
	kind delete cluster --name $(KIND_CLUSTER)

.PHONY: deploy-verified
deploy-verified: ## Deploy the verified image (should be admitted)
	kubectl apply -f deploy/verified.yaml

.PHONY: deploy-unsigned
deploy-unsigned: ## Deploy an unsigned image (should be DENIED)
	kubectl apply -f deploy/unsigned.yaml

# --- Meta ------------------------------------------------------------------
.PHONY: tools
tools: ## Print install hints for the supply-chain toolchain
	@echo "Install: syft, grype, cosign, kubectl, kind, kyverno"
	@echo "  https://github.com/anchore/syft"
	@echo "  https://github.com/anchore/grype"
	@echo "  https://github.com/sigstore/cosign"

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
