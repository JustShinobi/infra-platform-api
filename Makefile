KUSTOMIZE ?= kubectl kustomize
UV ?= uv

.PHONY: install lock test lint format render validate clean

install:
	$(UV) sync --frozen

lock:
	$(UV) lock

test:
	$(UV) run --frozen python -m unittest discover -s tests -v

lint:
	$(UV) run --frozen ruff check app tests
	$(UV) run --frozen ruff format --check app tests

format:
	$(UV) run ruff check --fix app tests
	$(UV) run ruff format app tests

render:
	mkdir -p rendered
	$(KUSTOMIZE) k8s/overlays/dev > rendered/dev.yaml
	$(KUSTOMIZE) k8s/overlays/prod > rendered/prod.yaml

validate: test lint render

clean:
	rm -rf rendered app/__pycache__ tests/__pycache__
