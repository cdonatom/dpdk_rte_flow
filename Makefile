# Makefile for building DPDK RTE Flow container with podman

# Default values
IMAGE_NAME ?= dpdk-rte-flow
VERSION ?= v4.20
BASE_IMAGE ?= registry.redhat.io/openshift4/dpdk-base-rhel9:$(VERSION)
DEBUG ?= false
REGISTRY ?= quay.io/cdonato

# Build the container with debug mode (default)
.PHONY: build
build:
	podman build --build-arg DEBUG=$(DEBUG) --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(IMAGE_NAME):$(VERSION) .

# Build the container with debug mode enabled
.PHONY: build-debug
build-debug:
	podman build --build-arg DEBUG=true --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(IMAGE_NAME):$(VERSION)-debug .

# Build the container without debug mode (release)
.PHONY: build-release
build-release:
	podman build --build-arg DEBUG=false --build-arg BASE_IMAGE=$(BASE_IMAGE) -t $(IMAGE_NAME):$(VERSION) .

.PHONY: push
push:
	podman push $(IMAGE_NAME):$(VERSION) $(REGISTRY)/$(IMAGE_NAME):$(VERSION)

.PHONY: push-debug
push-debug:
	podman push $(IMAGE_NAME):$(VERSION)-debug $(REGISTRY)/$(IMAGE_NAME):$(VERSION)-debug

# Clean up the container image
.PHONY: clean
clean:
	podman rmi $(IMAGE_NAME):$(VERSION) $(IMAGE_NAME):$(VERSION)-debug || true

# Show help
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  build          - Build container with DEBUG=$(DEBUG) (default: true)"
	@echo "  build-debug    - Build container with debug mode enabled"
	@echo "  build-release  - Build container without debug mode"
	@echo "  push           - Push the container image to the registry"
	@echo "  push-debug     - Push the container image with debug mode to the registry"
	@echo "  clean          - Remove the container image"
	@echo "  help           - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make build              # Build with default DEBUG=true"
	@echo "  make build DEBUG=false  # Build with DEBUG=false"
	@echo "  make build-debug        # Build with debug mode"
	@echo "  make build-release      # Build without debug mode"
