# Infra Platform API

Aplicação HTTP em Flask, servida por Gunicorn, empacotada em container e implantável com Kustomize. O projeto mantém a camada de aplicação pequena, enquanto Kubernetes, segurança e CI/CD recebem o foco principal.

## O que está incluído

- `GET /healthz`: health check usado pelas probes do Kubernetes;
- `GET /info`: versão, hostname do pod e valores injetados pelo ConfigMap;
- testes unitários e testes dos endpoints pelo test client do Flask;
- dependências fixadas com hashes e imagem multi-stage, enxuta e não-root;
- Kustomize com `base` e overlays `dev` e `prod`;
- GitHub Actions para testar, auditar dependências e imagem, validar schemas, executar o container endurecido e publicar no GHCR;
- documentação de implantação e relatório de decisões técnicas.

## Estrutura

```text
.
├── app/                     # API Python
├── tests/                   # testes unitários e HTTP
├── k8s/
│   ├── base/                # recursos Kubernetes reutilizáveis
│   └── overlays/            # ambientes dev e prod
├── .github/workflows/ci.yml # pipeline de CI e publicação
├── requirements.in         # dependências diretas
├── requirements.lock       # árvore completa fixada com hashes
├── Dockerfile              # build multi-stage + Gunicorn
├── DEPLOY.md
└── RELATORIO-TECNICO.md
```

## Execução local

Pré-requisito: Python 3.10 ou superior.

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --require-hashes -r requirements.lock
APP_ENV=local APP_MESSAGE="hello from local" python3 -m app.main
curl http://127.0.0.1:8080/healthz
curl http://127.0.0.1:8080/info
```

`python -m app.main` usa o servidor de desenvolvimento apenas para execução local. A imagem sempre inicia a aplicação com Gunicorn.

## Testes

```bash
make install
make test
```

Os testes usam o test client oficial do Flask e validam status, payload, headers, respostas de erro e leitura das variáveis de ambiente.

## Execução com Docker

```bash
docker build --build-arg APP_VERSION=local -t infra-platform-api:local .
docker run --rm -p 8080:8080 \
  -e APP_ENV=docker \
  -e APP_MESSAGE="hello from Docker" \
  infra-platform-api:local
```

Em outro terminal:

```bash
curl http://127.0.0.1:8080/info
```

As instruções completas para Kubernetes estão em [DEPLOY.md](DEPLOY.md), e as decisões e trade-offs em [RELATORIO-TECNICO.md](RELATORIO-TECNICO.md).

## Artefatos públicos

- repositório: <https://github.com/JustShinobi/infra-platform-api>;
- imagem: `ghcr.io/justshinobi/infra-platform-api:main`;
- versões implantáveis fixadas por digest nos overlays `dev` e `prod`.
