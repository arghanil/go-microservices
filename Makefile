AWS_ACCOUNT	:= "092896522805"
IMAGE_NAME	:= "internal-services"
REPOSITORY_NAME	:= "$(IMAGE_NAME)"
ECR_REPOSITORY	:= "$(AWS_ACCOUNT).dkr.ecr.us-west-2.amazonaws.com/$(REPOSITORY_NAME)"

check-var = $(if $(strip $($1)),,$(error var for "$1" is empty))
stack_lower := $(shell echo $(stack) | tr A-Z a-z)

default: help

require_stack:
	$(call check-var,stack)

require_tag:
	$(call check-var,tag)

go/compile: 			## compile go programs
						@CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o bin/main .

docker/tag/list:		## list the existing tagged images
						@aws ecr list-images --registry-id $(AWS_ACCOUNT) --repository-name $(REPOSITORY_NAME) --filter tagStatus=TAGGED | jq -M -r '.imageIds|.[]|.imageTag'

docker/build:			validate_tag ## build and tag the Docker image. vars:tag
						@docker build  -t $(IMAGE_NAME) .
						@docker tag $(REPOSITORY_NAME) $(ECR_REPOSITORY):$(tag)

validate_tag:			require_tag
						#@aws ecr list-images --registry-id $(AWS_ACCOUNT) --repository-name $(REPOSITORY_NAME) --filter tagStatus=TAGGED | jq -M -r '.imageIds|.[]|.imageTag' | tr '\n' ' ' | grep -q -v $(tag)[^-] || { echo "error using the tag"; exit 1;}

docker/push:			validate_tag ## push the Docker image to ECR. vars:tag
						@aws ecr get-login --region us-west-2 | sh -
						@docker push $(ECR_REPOSITORY):$(tag)

helm/install:           require_stack ## Deploy stack into kubernetes. vars: stack
	                    @helm install --name internal-services-$(stack_lower) --values=./chart/values/values-$(stack_lower).yaml ./chart

helm/delete:            require_stack ## delete stack from reference. vars: stack
	                    @helm delete  --purge internal-services-$(stack_lower)

deploy:                 require_tag require_stack ## Compiles, builds and deploys a stack for a tag. vars: tag, stack
						@CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o bin/main .
						@docker build  -t $(IMAGE_NAME) .
						@docker tag $(REPOSITORY_NAME) $(ECR_REPOSITORY):$(tag)
						@aws ecr get-login --region us-west-2 | sh -
						@docker push $(ECR_REPOSITORY):$(tag)
	                    @helm install --name internal-services-$(stack_lower) --values=./chart/values/values-$(stack_lower).yaml ./chart

redeploy:               require_tag require_stack ## Compiles, builds and deploys a stack for a tag. vars: tag, stack
						@CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o bin/main .
						@docker build  -t $(IMAGE_NAME) .
						@docker tag $(REPOSITORY_NAME) $(ECR_REPOSITORY):$(tag)
						@aws ecr get-login --region us-west-2 | sh -
						@docker push $(ECR_REPOSITORY):$(tag)
	                    @helm delete  --purge internal-services-$(stack_lower)
	                    @helm install --name internal-services-$(stack_lower) --values=./chart/values/values-$(stack_lower).yaml ./chart

help:					## this helps
						@awk 'BEGIN {FS = ":.*?## "} /^[\/a-zA-Z_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf "\033[36minternal-services \033[0m%-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
