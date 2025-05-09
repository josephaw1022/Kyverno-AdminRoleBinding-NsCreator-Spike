.DEFAULT_GOAL := help

CLUSTER_NAME ?= rbac-test
KYVERNO_NAMESPACE ?= kyverno
RBAC_FILE ?= manifests/rbac.yaml
POLICY_FILE ?= manifests/kyverno-policy.yaml
USERS := alice bob
USER_GROUP := dev-users

##@ Meta

.PHONY: help
help: ## Show help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z0-9_.-]+:.*##/ { printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2 } \
	/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Cluster

.PHONY: create-cluster
create-cluster: ## Create kind cluster (idempotent)
	@echo "🛠️  Ensuring kind cluster '$(CLUSTER_NAME)' exists..."
	@if kind get clusters | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "✅ Cluster exists."; \
	else \
		kind create cluster --name $(CLUSTER_NAME); \
	fi

.PHONY: delete-cluster
delete-cluster: ## Delete kind cluster
	@echo "🧨 Deleting kind cluster: $(CLUSTER_NAME)..."
	kind delete cluster --name $(CLUSTER_NAME)

##@ Kyverno

.PHONY: install-kyverno
install-kyverno: ## Install or upgrade Kyverno via Helm with debug flags
	@echo "🔧 Installing or upgrading Kyverno with debug logging..."
	@helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
	@helm repo update >/dev/null
	@helm upgrade --install kyverno kyverno/kyverno \
		-n $(KYVERNO_NAMESPACE) \
		--create-namespace \
		--set extraArgs[0]="--v=4" \
		--set extraArgs[1]="--dumpPayload=true"
	@echo "⏳ Waiting for ClusterPolicy CRD..."
	@kubectl wait --for=condition=Established crd/clusterpolicies.kyverno.io --timeout=60s


.PHONY: fix-kyverno
fix-kyverno: ## Grant Kyverno permission to manage RoleBindings
	@echo "🔐 Applying Kyverno RBAC fix for generate permissions..."
	kubectl apply -f manifests/kyverno-role-fix.yaml

.PHONY: apply-rbac
apply-rbac: ## Apply RBAC manifest
	kubectl apply -f $(RBAC_FILE)

.PHONY: apply-policy
apply-policy: ## Apply Kyverno policy
	kubectl apply -f $(POLICY_FILE)

.PHONY: apply-manifests
apply-manifests: apply-rbac fix-kyverno apply-policy ## Apply RBAC and Kyverno policy

##@ Users

.PHONY: generate-users
generate-users: ## Generate certs for all users
	@echo "🔏 Generating certs for: $(USERS)..."
	@mkdir -p certs
	CONTAINER=$$(docker ps --filter name=$(CLUSTER_NAME)-control-plane --format '{{.Names}}'); \
	docker cp $$CONTAINER:/etc/kubernetes/pki/ca.crt certs/ca.crt; \
	docker cp $$CONTAINER:/etc/kubernetes/pki/ca.key certs/ca.key; \
	for user in $(USERS); do \
		openssl genrsa -out certs/$$user.key 2048; \
		openssl req -new -key certs/$$user.key -out certs/$$user.csr -subj "/CN=$$user/O=$(USER_GROUP)"; \
		openssl x509 -req -in certs/$$user.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial -out certs/$$user.crt -days 365; \
	done

.PHONY: create-kubeconfigs
create-kubeconfigs: generate-users ## Create kubeconfigs for users
	@mkdir -p kubeconfigs
	@SERVER=$$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'); \
	for user in $(USERS); do \
		./scripts/create-kubeconfig.sh \
			--user $$user \
			--group $(USER_GROUP) \
			--cluster kind-$(CLUSTER_NAME) \
			--server $$SERVER \
			--ca certs/ca.crt \
			--cert certs/$$user.crt \
			--key certs/$$user.key \
			--output kubeconfigs/$$user.yaml; \
	done

##@ Testing

.PHONY: test-alice
test-alice: ## Test alice's access
	kubectl --kubeconfig=kubeconfigs/alice.yaml create ns alice-ns || true
	kubectl --kubeconfig=kubeconfigs/alice.yaml -n alice-ns create deployment nginx --image=nginx || true

.PHONY: test-bob
test-bob: ## Test bob's access
	kubectl --kubeconfig=kubeconfigs/bob.yaml get ns
	kubectl --kubeconfig=kubeconfigs/bob.yaml create ns bob-ns || true
	kubectl --kubeconfig=kubeconfigs/bob.yaml -n bob-ns create deployment busybox --image=busybox || true

##@ Utilities

.PHONY: make-scripts-executable
make-scripts-executable: ## Ensure all scripts are executable
	@echo "🔧 Making all scripts executable..."
	@chmod +x ./scripts/*.sh


.PHONY: reset-users
reset-users: ## Remove all generated certs and kubeconfigs
	@echo "🧹 Cleaning up user certs and kubeconfigs..."
	@rm -rf certs/*.key certs/*.crt certs/*.csr certs/ca.* certs/*.srl
	@rm -rf kubeconfigs/*.yaml


##@ Workflow

.PHONY: up
up: create-cluster install-kyverno apply-manifests make-scripts-executable create-kubeconfigs ## Full cluster and user setup


.PHONY: test
test: test-alice test-bob ## Run user test scenarios


.PHONY: clean
clean: ## Remove certs, kubeconfigs, and delete the kind cluster
	@echo "🧼 Cleaning up certs, kubeconfigs, and Kind cluster..."
	@rm -rf certs/ kubeconfigs/
	@kind delete cluster --name $(CLUSTER_NAME) || true



.PHONY: debug-policy
debug-policy: ## Print current policy + RBAC fix + check alice-ns RoleBindings
	@echo "📄 Kyverno Policy:"
	@cat $(POLICY_FILE) | yq
	@echo "\n📄 Kyverno RBAC Fix:"
	@cat manifests/kyverno-role-fix.yaml | yq
	@echo "\n🔎 RoleBindings in namespace 'alice-ns':"
	@kubectl get rolebinding -n alice-ns -o wide || true
