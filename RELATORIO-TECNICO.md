# Relatório técnico — Infra Platform API

## Visão geral

O projeto tem quatro partes: a API em Flask, a imagem de contêiner, os manifestos Kubernetes organizados com Kustomize e o pipeline no GitHub Actions. Mantive a aplicação pequena para que as decisões de infraestrutura ficassem fáceis de localizar e testar.

Além da validação local e do pipeline, implantei a imagem publicada em um cluster k3s. Essa etapa ajudou a verificar os controles do contêiner em condições reais e revelou um ajuste necessário no Gunicorn, descrito mais adiante.

## Aplicação

A API expõe dois endpoints:

- `/healthz` responde ao health check usado pelas probes do Kubernetes;
- `/info` mostra versão, ambiente, mensagem configurada e hostname do pod.

Escolhi Flask porque ele oferece o necessário para este serviço — roteamento, tratamento de respostas e um bom cliente de testes — sem trazer componentes que não seriam usados. A application factory deixa a criação da aplicação isolada e facilita os testes. Respostas 404 também usam JSON, mantendo o mesmo formato da API.

No contêiner, a aplicação roda com Gunicorn em um worker e quatro threads. É uma configuração suficiente para este serviço leve e cabe com folga nos limites definidos nos manifestos. O heartbeat do Gunicorn usa `/dev/shm`, e o control socket foi desabilitado. Com isso, o processo funciona com o sistema de arquivos raiz somente leitura, sem precisar abrir mais um volume gravável no pod.

Flask e Gunicorn acrescentam dependências quando comparados a um servidor feito apenas com a biblioteca padrão. Aqui, a troca vale a pena pela clareza e pelo comportamento de produção. FastAPI faria mais sentido se houvesse payloads com schemas, validação de dados ou documentação OpenAPI, requisitos que não existem nesta API.

## Imagem de contêiner

O Dockerfile usa `python:3.14-alpine` fixado por digest e separa construção e execução em dois estágios. O primeiro estágio copia uma versão também fixada do `uv` e instala as dependências com `uv sync --frozen --no-dev`. O segundo recebe apenas o ambiente virtual e o código da aplicação.

A imagem final:

- executa como UID e GID 10001;
- não contém `uv`, `pip` ou `setuptools`;
- não grava arquivos `.pyc`;
- inclui um health check para uso fora do Kubernetes;
- recebe o SHA do commit em `APP_VERSION`;
- tem aproximadamente 17,7 MiB no formato comprimido publicado no GHCR.

O Alpine foi uma escolha adequada porque as dependências atuais não exigem extensões nativas. A principal ressalva é o uso de musl: se o projeto passasse a depender de bibliotecas como NumPy ou de drivers distribuídos apenas para glibc, uma base `python:slim` seria mais previsível, mesmo com uma imagem maior.

O pipeline publica `main` e `sha-<commit>`, mas os overlays não dependem de tags mutáveis: ambos fixam o digest OCI da imagem promovida. Assim, o conteúdo implantado não muda se uma tag for atualizada no registry. O Dependabot acompanha semanalmente as dependências do `uv`, a imagem base e as actions usadas pelo pipeline.

## Kubernetes e Kustomize

A base reúne Deployment, Service ClusterIP, ConfigMap, Ingress e ServiceAccount. Os overlays alteram apenas o que varia entre ambientes:

- `dev` usa uma réplica, recursos menores, namespace e host próprios;
- `prod` usa duas réplicas, mais recursos, distribuição entre nós e PodDisruptionBudget.

O pod segue os controles do Pod Security Standard `restricted`: roda como usuário não-root, usa o perfil seccomp padrão, bloqueia elevação de privilégio, remove todas as capabilities e mantém o sistema de arquivos raiz somente leitura. O token do ServiceAccount não é montado porque a aplicação não acessa a API do Kubernetes.

Readiness e liveness consultam `/healthz` com temporizações diferentes. Requests orientam o agendamento e limits impedem consumo sem controle. Durante uma atualização, `maxUnavailable: 0` mantém a instância atual disponível até que a nova esteja pronta. Os ConfigMaps gerados pelo Kustomize recebem um hash no nome; uma alteração de configuração atualiza a referência no pod e inicia o rollout sem intervenção manual.

Não incluí HPA porque não há teste de carga nem histórico de uso que sustente um limite de escala. Sem esses dados, qualquer valor seria um chute e poderia escalar cedo ou tarde demais. A NetworkPolicy também ficou fora da base: sua configuração depende do CNI, do Ingress Controller e dos fluxos permitidos no cluster de destino. Uma política genérica poderia bloquear as probes ou o tráfego do Ingress. Com esses fluxos conhecidos, ela pode ser adicionada sem esse risco.

## Pipeline de CI/CD

O workflow roda em pushes e pull requests para `main` e separa as permissões em três jobs.

O primeiro job instala Python 3.14 e uma versão fixada do `uv`, restaura o cache, sincroniza o ambiente pelo lockfile e executa os testes. Em seguida, o Ruff verifica lint e formatação, os dois overlays são renderizados e os recursos passam pelo kubeconform em modo estrito. O `pip-audit` recebe uma exportação temporária com hashes gerada a partir do `uv.lock`; ela não é versionada nem funciona como uma segunda lista de dependências.

O segundo job constrói a imagem e inicia o contêiner com UID 10001, raiz somente leitura, nenhuma capability e `no-new-privileges`. O smoke test verifica os dois endpoints, a configuração recebida e a identidade efetiva do processo. Depois, o Trivy bloqueia vulnerabilidades corrigíveis de severidade `HIGH` ou `CRITICAL`.

O terceiro job só roda em pushes e depois dos dois anteriores. É o único a receber `packages: write` e publica a imagem no GHCR. As permissões globais ficam limitadas à leitura do conteúdo, e o checkout não mantém as credenciais Git. Builds obsoletos da mesma referência são cancelados. O BuildKit também gera SBOM e provenance para registrar como o artefato foi produzido.

A imagem é construída no job de teste e novamente no de publicação porque os jobs não compartilham o daemon Docker. Isso custa alguns segundos, reduzidos pelo cache, mas evita conceder permissão de publicação ao job que executa código da imagem e garante que nada seja enviado antes dos testes.

## Operação e observabilidade

Os logs do Gunicorn seguem para stdout e stderr, onde podem ser coletados pela plataforma. O endpoint `/info` ajuda a identificar rapidamente a versão, o ambiente e o pod que respondeu à requisição.

Não adicionei Prometheus, tracing ou dashboards porque não há uma plataforma de observabilidade definida e o serviço é pequeno. Em uma operação contínua, o próximo passo seria estruturar os logs em JSON e acompanhar taxa de requisições, erros, duração e saturação, com alertas ligados a objetivos de serviço.

## Validação realizada

A validação foi feita em três níveis: ambiente local, GitHub Actions e cluster k3s.

### Código, manifestos e imagem

- Os sete testes da aplicação passaram, cobrindo funções, valores padrão, endpoints, cabeçalhos e erros 404 e 405 em JSON.
- As oito dependências diretas e transitivas de runtime foram instaladas pelo `uv.lock`.
- O Ruff não encontrou problemas de lint ou formatação em `app/` e `tests/`.
- Os overlays `dev` e `prod` foram renderizados com Kustomize.
- Os 13 recursos renderizados passaram pelo kubeconform em modo estrito com os schemas do Kubernetes 1.36.
- O contêiner respondeu corretamente aos endpoints sob as mesmas restrições essenciais usadas no pod.
- O `pip-audit` não encontrou vulnerabilidades conhecidas nas dependências declaradas.
- O Trivy não encontrou vulnerabilidades corrigíveis `HIGH` ou `CRITICAL` na imagem final.
- Os três jobs do workflow foram concluídos com sucesso.
- A imagem foi publicada com SBOM e provenance e seu manifesto OCI pôde ser lido sem autenticação.
- Secret Scanning, Push Protection e as atualizações de segurança do Dependabot estão ativos no repositório.

As execuções do pipeline estão disponíveis em <https://github.com/JustShinobi/infra-platform-api/actions/workflows/ci.yml>.

### Cluster k3s

A imagem foi baixada diretamente do GHCR, sem pull secret ou importação manual. No cluster:

- o namespace foi aceito com Pod Security Standard `restricted`;
- o rollout terminou com o pod `1/1 Ready` e sem reinícios;
- readiness e liveness responderam com HTTP 200;
- o Service respondeu aos dois endpoints;
- `/info` retornou o SHA completo, a mensagem do ConfigMap e o hostname do pod;
- o digest em execução correspondeu à imagem promovida;
- o processo rodou como `uid=10001 gid=10001`;
- master e worker do Gunicorn usaram `gthread` e `/dev/shm`;
- uma tentativa de escrita em `/` falhou com `Read-only file system`;
- os logs finais não apresentaram erros, exceções ou tracebacks.

Na primeira implantação, o heartbeat padrão do Gunicorn tentou usar um caminho incompatível com a raiz somente leitura. O control socket também tentava criar um arquivo no mesmo sistema de arquivos. A configuração atual move o heartbeat para `/dev/shm` e desabilita o socket, que não é necessário neste serviço. O smoke test do pipeline reproduz essas restrições para evitar que o problema volte.

O Ingress Controller compartilhado do laboratório deixou de reconciliar a rota depois de um rollout. As probes e o caminho Service → Pod continuaram respondendo com HTTP 200, o que isolou o problema no controller. Não reiniciei esse componente porque ele atende outros workloads; a aplicação foi validada diretamente pelo Service.

## Publicação e próximos passos

O código está disponível em <https://github.com/JustShinobi/infra-platform-api> e a imagem pública em `ghcr.io/justshinobi/infra-platform-api`. Ambos podem ser avaliados sem credenciais.

Algumas evoluções dependem do ambiente em que o serviço será operado:

- assinar a imagem com Cosign e exigir a assinatura na admissão;
- criar uma NetworkPolicy alinhada ao CNI e aos fluxos reais;
- configurar DNS e TLS no Ingress;
- definir métricas e alertas a partir de SLOs;
- automatizar a promoção entre ambientes com GitOps.

Esses itens não foram incluídos agora porque exigem decisões externas ao projeto. A estrutura atual permite adicioná-los sem alterar a aplicação.
