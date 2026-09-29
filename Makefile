KUSTOMIZE ?= kubectl kustomize

.PHONY: install test render validate clean

install:
	python3 -m pip install --require-hashes -r requirements.lock

test:
	python3 -m unittest discover -s tests -v

render:
	mkdir -p rendered
	$(KUSTOMIZE) k8s/overlays/dev > rendered/dev.yaml
	$(KUSTOMIZE) k8s/overlays/prod > rendered/prod.yaml

validate: test render
	python3 -m compileall -q app tests

clean:
	rm -rf rendered app/__pycache__ tests/__pycache__
