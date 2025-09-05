.PHONY: deploy

deploy:
	./scripts/deploy.sh

run_app:
	mix run --no-halt

run_dev:
	iex -S mix

.PHONY: clean_port
# List of ports to clean
PORTS = 5005 4004

clean_port:
	@echo "Checking and cleaning ports: $(PORTS)"
	@for port in $(PORTS); do \
		echo "Checking port $$port..."; \
		PID=$$(lsof -t -i :$$port); \
		if [ -n "$$PID" ]; then \
			echo "Killing process $$PID using port $$port"; \
			kill -9 $$PID && echo "✓ Killed $$PID" || echo "✗ Failed to kill $$PID"; \
		else \
			echo "Port $$port is free"; \
		fi; \
	done
