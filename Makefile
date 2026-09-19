HOST ?= workstation

.PHONY: help
help:
	@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | column -t -s "$$(printf '\t')"

.PHONY: lint
lint: ## check every document without touching the host
	podcd lint --host $(HOST) .

.PHONY: validate
validate: ## compile what the agent sees for $(HOST) (needs `make bootstrap` first)
	podcd validate --host $(HOST) -o yaml

.PHONY: get
get: ## list what this repository defines
	podcd get all --repo .

.PHONY: bootstrap
bootstrap: ## create the network, seed agent.env, install and start the agent
	./bootstrap/bootstrap.sh --host $(HOST)

.PHONY: plan
plan: ## what the agent would change
	podcd plan

.PHONY: reconcile
reconcile: ## make this host match Git now, instead of waiting for the loop
	podcd reconcile

.PHONY: status
status: ## last reconcile and per-application unit state
	podcd status

.PHONY: health
health: ## what podman says about the running applications
	podcd health

.PHONY: logs
logs: ## agent logs
	podcd logs

.PHONY: gpu-check
gpu-check: ## prove the ollama container actually sees the GPU
	podman exec ollama-ollama /usr/lib/wsl/lib/nvidia-smi -L || \
	  echo "no GPU in the container - check gpu.mode in values/common.yaml"

.PHONY: models
models: ## models currently resident
	curl -fsS http://127.0.0.1:11434/api/tags | python3 -m json.tool

.PHONY: endpoints
endpoints: ## what is listening, and how to reach it
	@echo "ollama      http://127.0.0.1:11434"
	@echo "litellm     http://127.0.0.1:4000/v1"
	@echo "open-webui  http://127.0.0.1:3000"
	@grep '^LITELLM_MASTER_KEY=' $$HOME/.config/podcd/agent.env 2>/dev/null || true

.PHONY: teardown
teardown: ## stop and remove everything, and uninstall the agent
	podcd teardown --purge-state --purge-config -y
