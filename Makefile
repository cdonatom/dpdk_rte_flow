# Makefile for building DPDK RTE Flow container with podman

# Default values
BASE_IMAGE_NAME ?= dpdk_base
IMAGE_NAME ?= dpdk_rte_raw
DPDK_VERSION ?= 26.03-rc1
VERSION ?= v4.20
BASE_IMAGE ?= localhost/$(BASE_IMAGE_NAME):$(DPDK_VERSION)
DEBUG ?= false
REGISTRY ?= quay.io/cdonato

# Build the DPDK base image (optional, standalone)
.PHONY: build-base
build-base:
	podman build -f Containerfile_dpdk_base -t $(BASE_IMAGE_NAME):$(DPDK_VERSION) .

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

# Build both base and application images
.PHONY: build-all
build-all: build-base build

# Push base image to registry
.PHONY: push-base
push-base:
	podman push $(BASE_IMAGE_NAME):$(DPDK_VERSION) $(REGISTRY)/$(BASE_IMAGE_NAME):$(DPDK_VERSION)

# Push application image to registry
.PHONY: push
push:
	podman push $(IMAGE_NAME):$(VERSION) $(REGISTRY)/$(IMAGE_NAME):$(VERSION)

.PHONY: push-debug
push-debug:
	podman push $(IMAGE_NAME):$(VERSION)-debug $(REGISTRY)/$(IMAGE_NAME):$(VERSION)-debug

# Push all images to registry
.PHONY: push-all
push-all: push-base push

# Clean up the container images
.PHONY: clean
clean:
	podman rmi $(IMAGE_NAME):$(VERSION) $(IMAGE_NAME):$(VERSION)-debug $(BASE_IMAGE_NAME):$(DPDK_VERSION) || true

# Show help
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  build-base     - Build the DPDK base image"
	@echo "  build          - Build application container with DEBUG=$(DEBUG) (builds base first)"
	@echo "  build-debug    - Build application container with debug mode enabled"
	@echo "  build-release  - Build application container without debug mode"
	@echo "  build-all      - Build both base and application images"
	@echo "  push-base      - Push the base image to the registry"
	@echo "  push           - Push the application image to the registry"
	@echo "  push-debug     - Push the application image with debug mode to the registry"
	@echo "  push-all       - Push all images to the registry"
	@echo "  clean          - Remove all container images"
	@echo "  help           - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  BASE_IMAGE_NAME - Base image name (default: $(BASE_IMAGE_NAME))"
	@echo "  IMAGE_NAME      - Application image name (default: $(IMAGE_NAME))"
	@echo "  DPDK_VERSION    - DPDK version for base image (default: $(DPDK_VERSION))"
	@echo "  VERSION         - Application version tag (default: $(VERSION))"
	@echo "  DEBUG           - Enable debug symbols (default: $(DEBUG))"
	@echo "  REGISTRY        - Container registry (default: $(REGISTRY))"
	@echo ""
	@echo "Examples:"
	@echo "  make build-base         # Build only the DPDK base image"
	@echo "  make build              # Build base + application with default DEBUG=false"
	@echo "  make build DEBUG=true   # Build with DEBUG=true"
	@echo "  make build-all          # Build both base and application"
	@echo "  make push-all           # Push all images to registry"
