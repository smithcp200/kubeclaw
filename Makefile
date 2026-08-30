SHELL := /bin/bash

GO ?= go
GOTESTFMT_PKG ?= github.com/gotesttools/gotestfmt/v2/cmd/gotestfmt@latest
CLI_PKG ?= ./cmd/kubeclaw/...

.PHONY: test-cli test-cli-pretty test-go test-go-pretty test-scripts

# Image bootstrap scripts. Plain node, no framework, so it runs anywhere node
# does. Covers merge-json5's RFC 7386 semantics, where a leaked `null` becomes a
# gateway that will not start.
test-scripts:
	node images/kubeclaw/scripts/merge-json5.test.js

test-cli:
	$(GO) test -count=1 $(CLI_PKG)

test-cli-pretty:
	@if ! command -v gotestfmt >/dev/null 2>&1; then \
		echo "Installing gotestfmt..."; \
		$(GO) install $(GOTESTFMT_PKG); \
	fi
	@set -o pipefail; $(GO) test -count=1 -json $(CLI_PKG) | gotestfmt

test-go:
	$(GO) test -count=1 ./...

test-go-pretty:
	@if ! command -v gotestfmt >/dev/null 2>&1; then \
		echo "Installing gotestfmt..."; \
		$(GO) install $(GOTESTFMT_PKG); \
	fi
	@set -o pipefail; $(GO) test -count=1 -json ./... | gotestfmt
