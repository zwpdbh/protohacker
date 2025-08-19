.PHONY: deploy

deploy:
	./scripts/deploy.sh

run_app:
	mix run --no-halt
