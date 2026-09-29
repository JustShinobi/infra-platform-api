# Infra Platform API

Este projeto reúne uma API pequena em Flask e a infraestrutura necessária para executá-la em Kubernetes. A regra de negócio é propositalmente curta: o foco está no empacotamento, na segurança, no processo de implantação e na automação do pipeline.

## Visão geral

- `GET /healthz` informa se a aplicação está pronta para receber tráfego.
- `GET /info` retorna a versão, o hostname do pod e os valores recebidos pelo ConfigMap.
- Os testes cobrem as funções e o comportamento HTTP da API.
- O `uv.lock` mantém as dependências reproduzíveis no desenvolvimento, no CI e na construção da imagem.
- A configuração do Kubernetes usa uma base comum e overlays para `dev` e `prod`.
- O GitHub Actions testa o código, valida os manifestos, verifica vulnerabilidades e publica a imagem no GHCR.

## Estrutura do repositório

```text
.
├── app/                     # aplicação Flask
├── tests/                   # testes unitários e dos endpoints
├── k8s/
│   ├── base/                # recursos compartilhados
│   └── overlays/            # configurações de dev e prod
├── .github/workflows/ci.yml # pipeline de CI e publicação
├── pyproject.toml           # metadados e dependências diretas
├── uv.lock                  # resolução completa das dependências
├── Dockerfile               # construção da imagem e execução com Gunicorn
├── DEPLOY.md
└── RELATORIO-TECNICO.md
```

## Rodando localmente

É necessário ter Python 3.14 e `uv` 0.12 instalados.

```bash
uv sync --frozen
APP_ENV=local APP_MESSAGE="execução local" uv run --frozen python -m app.main
curl http://127.0.0.1:8080/healthz
curl http://127.0.0.1:8080/info
```

Esse comando usa o servidor de desenvolvimento do Flask. A imagem de contêiner inicia a aplicação com Gunicorn.

## Instalando e testando

```bash
make install
make test
make lint
```

Os testes usam o cliente de testes do Flask para verificar status, payloads, cabeçalhos, respostas de erro e leitura das variáveis de ambiente. O Ruff valida lint e formatação com `make lint`; para aplicar correções locais, use `make format`.

Para alterar uma dependência, edite `pyproject.toml` e execute `uv lock`. O arquivo `uv.lock` é a fonte usada em todos os ambientes; a imagem final não leva `uv`, `pip` ou `setuptools`.

## Rodando com Docker

```bash
docker build --build-arg APP_VERSION=local -t infra-platform-api:local .
docker run --rm -p 8080:8080 \
  -e APP_ENV=docker \
  -e APP_MESSAGE="execução via Docker" \
  infra-platform-api:local
```

Em outro terminal:

```bash
curl http://127.0.0.1:8080/info
```

O passo a passo para Kubernetes está em [DEPLOY.md](DEPLOY.md). O contexto das escolhas técnicas e os limites da solução estão em [RELATORIO-TECNICO.md](RELATORIO-TECNICO.md).

## Artefatos públicos

- Repositório: <https://github.com/JustShinobi/infra-platform-api>
- Imagem: `ghcr.io/justshinobi/infra-platform-api:main`
- Os overlays `dev` e `prod` apontam para versões imutáveis da imagem por digest.
- Uma nova imagem gera um PR de promoção com o digest atualizado nos dois overlays.
