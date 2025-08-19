.PHONY: run_deploy

run_deploy:
	@echo "Logging into Azure Container Registry..."
	az acr login --name protohackeracr

	@echo "Getting ACR login server..."
	ACR_LOGIN_SERVER=$$(az acr show --name protohackeracr --query loginServer --output tsv); \
	echo "ACR Login Server: $$ACR_LOGIN_SERVER"

	@echo "Building Docker image..."
	docker buildx build -t protohacker:latest .

	@echo "Generating dynamic timestamp tag..."
	TIMESTAMP=$$(date +'%Y-%m-%d-%H-%M-%S'); \
	IMAGE_NAME=$$ACR_LOGIN_SERVER/protohacker:$$TIMESTAMP; \
	echo "Tagging image as $$IMAGE_NAME"; \
	docker tag protohacker:latest $$IMAGE_NAME

	@echo "Pushing image to ACR..."
	docker push $$IMAGE_NAME

	@echo "Deployment completed with tag: $$TIMESTAMP"

run_app:
	mix run --no-halt
