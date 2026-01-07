.DEFAULT_GOAL := help

.PHONY: help
help: ## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z\/_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: build
build: ## Build CLI (debug)
	@zig build

.PHONY: release
release: ## Build CLI (release)
	@zig build -Doptimize=ReleaseFast

.PHONY: run
run: ## Run formatter with arguments (ARGS=...)
	@zig build run -- $(ARGS)

.PHONY: fmt
fmt: ## Format Zig source code
	@zig fmt src/

##@ Testing/Linting

.PHONY: can-release
can-release: lint test ## Run all CI checks (lint + test)

.PHONY: lint
lint: ## Run zig fmt check
	@zig fmt --check src/

.PHONY: test
test: ## Run all tests
	@zig build test --summary all

##@ Cross-compilation

VERSION ?= dev

.PHONY: build/linux-amd64
build/linux-amd64: ## Build for Linux x86_64 (static)
	@zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseFast -Dversion=$(VERSION)

.PHONY: build/linux-arm64
build/linux-arm64: ## Build for Linux ARM64 (static)
	@zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseFast -Dversion=$(VERSION)

.PHONY: build/macos-amd64
build/macos-amd64: ## Build for macOS x86_64
	@zig build -Dtarget=x86_64-macos -Doptimize=ReleaseFast -Dversion=$(VERSION)

.PHONY: build/macos-arm64
build/macos-arm64: ## Build for macOS ARM64
	@zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast -Dversion=$(VERSION)

.PHONY: build/wasm
build/wasm: ## Build WebAssembly module (WASI)
	@zig build -Dtarget=wasm32-wasi -Doptimize=ReleaseFast -Dversion=$(VERSION)
