.DEFAULT_GOAL := help
SHELL         := /usr/bin/env bash

.PHONY: help lint validate-json validate-yaml shellcheck fmt-check \
        secrets-scan-staged lefthook-bootstrap lefthook-install hooks setup

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

lint: ## Lint workflow YAML with actionlint
	@command -v actionlint >/dev/null 2>&1 || { \
		echo "ERROR: actionlint not found. Install from https://github.com/rhysd/actionlint"; exit 1; }
	actionlint

validate-json: ## Validate renovate.json and all renovate/*.json preset files
	@python3 -c "
	import json, glob, sys
	files = sorted(['renovate.json'] + glob.glob('renovate/*.json'))
	failed = []
	for f in files:
	    try:
	        json.load(open(f))
	        print(f'  OK  {f}')
	    except json.JSONDecodeError as e:
	        print(f'  FAIL {f}: {e}')
	        failed.append(f)
	if failed:
	    sys.exit(1)
	print(f'All {len(files)} JSON configs valid.')
	"

validate-yaml: ## Validate lefthook.yml and all lefthook/*.yml and golangci/*.yml files
	@python3 -c "
	import yaml, glob, sys
	files = sorted(['lefthook.yml'] + glob.glob('lefthook/*.yml') + glob.glob('golangci/*.yml'))
	failed = []
	for f in files:
	    try:
	        yaml.safe_load(open(f))
	        print(f'  OK  {f}')
	    except yaml.YAMLError as e:
	        print(f'  FAIL {f}: {e}')
	        failed.append(f)
	if failed:
	    sys.exit(1)
	print(f'All {len(files)} YAML configs valid.')
	"

fmt-check: lint validate-json validate-yaml ## Run all local validation checks

shellcheck: ## Lint shell scripts
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -x create_prs.sh create_ci_tooling_prs.sh scripts/bootstrap_lefthook.sh; \
	else \
	  echo "shellcheck not found; skipping"; \
	fi

secrets-scan-staged: ## Scan staged files for secrets
	@command -v gitleaks >/dev/null 2>&1 || { \
		echo "ERROR: gitleaks not found. Install from https://github.com/gitleaks/gitleaks#installing"; exit 1; }
	gitleaks protect --staged --redact

lefthook-bootstrap: ## Download lefthook binary to .bin/
	bash ./scripts/bootstrap_lefthook.sh

lefthook-install: ## Install git hooks via lefthook
	.bin/lefthook install

hooks: lefthook-bootstrap lefthook-install ## Bootstrap and install all git hooks

setup: hooks ## Install hooks and verify required tools
	@command -v actionlint >/dev/null 2>&1 || { \
		echo ""; echo "ACTION REQUIRED: actionlint is not installed."; \
		echo "Install from https://github.com/rhysd/actionlint then re-run 'make setup'."; \
		echo ""; exit 1; }
	@command -v gitleaks >/dev/null 2>&1 || { \
		echo ""; echo "ACTION REQUIRED: gitleaks is not installed."; \
		echo "Install from https://github.com/gitleaks/gitleaks#installing then re-run 'make setup'."; \
		echo ""; exit 1; }
	@echo "Dev environment ready."
