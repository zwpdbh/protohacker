.PHONY: help setup server dev test format format.check precommit \
        deps.get deps.update clean check quality credo dialyzer dialyzer.setup \
        deploy clean_port

# Default target - show help
help:
	@echo "Available commands:"
	@echo ""
	@echo "Setup & Development:"
	@echo "  make setup          - Initial project setup (deps.get)"
	@echo "  make server         - Start application with IEx (iex -S mix)"
	@echo "  make dev            - Alias for 'make server'"
	@echo "  make run_app        - Run application without IEx"
	@echo ""
	@echo "Testing & Quality:"
	@echo "  make test           - Run tests"
	@echo "  make test.full      - Run tests + credo + dialyzer (slow)"
	@echo "  make format         - Format code"
	@echo "  make format.check   - Check if code is formatted"
	@echo "  make check          - Run all quality checks (format, dialyzer, credo)"
	@echo "  make quality        - Same as check"
	@echo "  make precommit      - Run full precommit suite"
	@echo ""
	@echo "Static Analysis:"
	@echo "  make credo          - Run Credo (strict mode)"
	@echo "  make dialyzer       - Run Dialyzer type checking"
	@echo "  make dialyzer.setup - Setup Dialyzer PLT (first time)"
	@echo ""
	@echo "Dependencies:"
	@echo "  make deps.get       - Get Elixir dependencies"
	@echo "  make deps.update    - Update Elixir dependencies"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make clean_port     - Clean ports 5005 and 4004"
	@echo "  make deploy         - Deploy application"

# Setup and Installation
# ----------------------

setup: deps.get
	@echo "✅ Project setup complete"

deps.get:
	mix deps.get

deps.update:
	mix deps.update --all

# Development Server
# ------------------

server:
	iex -S mix

dev: server

run_app:
	mix run --no-halt

# Testing & Quality
# -----------------

test:
	mix test

test.full: test credo dialyzer
	@echo "✅ Full test suite passed (including static analysis)"

format:
	mix format

format.check:
	mix format --check-formatted

check: format.check quality
	@echo "✅ All quality checks passed"

quality: credo dialyzer
	@echo "✅ Code quality checks passed"

precommit:
	mix precommit

# Static Analysis
# ---------------

credo:
	mix credo --strict

dialyzer:
	mix dialyzer.check

dialyzer.setup:
	mix dialyzer.setup

# Deployment
# ----------

deploy:
	./scripts/deploy.sh

# Utilities
# ---------

clean:
	mix clean
	rm -rf _build/
	@echo "✅ Build artifacts cleaned"

clean_port:
	@echo "Checking and cleaning ports: 5005 4004"
	@for port in 5005 4004; do \
		echo "Checking port $$port..."; \
		PID=$$(lsof -t -i :$$port); \
		if [ -n "$$PID" ]; then \
			echo "Killing process $$PID using port $$port"; \
			kill -9 $$PID && echo "✓ Killed $$PID" || echo "✗ Failed to kill $$PID"; \
		else \
			echo "Port $$port is free"; \
		fi; \
	done
