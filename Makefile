KUSTOMIZE ?= kubectl kustomize
UV ?= uv

.PHONY: install lock test render validate clean

install:
	$(UV) sync --frozen

lock:
	$(UV) lock

test:
	$(UV) run --frozen python -m unittest discover -s tests -v

render:
	mkdir -p rendered
	$(KUSTOMIZE) k8s/overlays/dev > rendered/dev.yaml
	$(KUSTOMIZE) k8s/overlays/prod > rendered/prod.yaml

validate: test render
	$(UV) run --frozen python -m compileall -q app tests

clean:
	rm -rf rendered app/__pycache__ tests/__pycache__
