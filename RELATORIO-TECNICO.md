# Relatório técnico — Infra Platform API

## 1. Resumo da solução

Foi construída uma API HTTP em Python, uma imagem de container endurecida, manifests Kubernetes reutilizáveis com Kustomize e um pipeline GitHub Actions. A solução atende aos endpoints, ConfigMap, Deployment, Service, Ingress, probes, recursos, overlays, testes, build e publicação solicitados. A validação adicional em k3s é registrada como evidência operacional sem versionar detalhes específicos do laboratório.

## 2. Aplicação

A API expõe `/healthz` e `/info`. O segundo endpoint demonstra configuração externa por meio de `APP_ENV` e `APP_MESSAGE`, além de expor versão e hostname. A aplicação usa Flask 3.1 com application factory; isso mantém criação e testes isolados e evita acoplamento de configuração. O handler 404 também responde JSON, preservando o contrato de API.

**Decisão:** Flask oferece roteamento, ciclo de resposta, test client e um caminho natural de evolução sem impor ORM, validação ou estrutura excessiva. A execução local pode usar o servidor de desenvolvimento, mas o container executa Gunicorn com um worker e quatro threads. Essa configuração oferece concorrência suficiente para o serviço leve sem desperdiçar memória dentro dos limites definidos no Kubernetes. O diretório temporário dos workers aponta para `/dev/shm`: o heartbeat permanece em memória e o processo é compatível com `readOnlyRootFilesystem` sem adicionar um volume gravável ao pod. O control socket do Gunicorn foi desabilitado porque não é usado pela operação do serviço e exigiria outro caminho gravável.

**Trade-off:** Flask e Gunicorn introduzem dependências e aumentam um pouco a imagem e a superfície de atualização. Para compensar, versões diretas e transitivas são fixadas com hashes em `requirements.lock`. FastAPI seria vantajoso com schemas, validação de payload ou OpenAPI; não há esses requisitos neste projeto.

## 3. Container

A imagem usa `python:3.13-alpine` fixada por digest e build multi-stage. O primeiro estágio instala a árvore Flask/Gunicorn com `--require-hashes`; o estágio final recebe somente os pacotes instalados e a aplicação, remove `pip`, `setuptools`, `ensurepip` e dependências vendorizadas desnecessárias, e executa como UID/GID 10001. `.dockerignore` reduz o contexto de build. `PYTHONDONTWRITEBYTECODE` permite root filesystem somente leitura no Kubernetes. Um health check nativo também cobre a execução fora do Kubernetes. Dependabot verifica semanalmente dependências Python, imagem base e GitHub Actions para que a reprodutibilidade não congele correções.

**Trade-off:** Alpine é pequena, mas usa musl. Isso pode dificultar extensões Python nativas; como a aplicação não possui dependências nativas, o benefício de tamanho prevalece. Em uma aplicação com NumPy, drivers ou wheels glibc, `python:slim` seria mais previsível.

A tag `main` é conveniente para desenvolvimento; cada build também recebe uma tag `sha-<commit>`. Como tags podem ser reassociadas no registry, o overlay de produção vai além e fixa o digest OCI do build promovido. O build recebe o SHA completo em `APP_VERSION`, permitindo confirmar pelo endpoint qual código originou o artefato em execução.

## 4. Kubernetes e Kustomize

A base contém Deployment, Service ClusterIP, ConfigMap, Ingress e ServiceAccount. O pod aplica controles compatíveis com o Pod Security Standard `restricted`: usuário não-root, seccomp padrão, sem elevação de privilégio, sem capabilities e filesystem somente leitura. O token da ServiceAccount não é montado, porque a aplicação não acessa a API do Kubernetes.

Readiness e liveness usam `/healthz`, com temporizações diferentes. Requests ajudam o scheduler; limits protegem o nó. O rollout impede indisponibilidade (`maxUnavailable: 0`) e mantém somente três revisões.

Os overlays divergem de forma real:

- `dev`: namespace próprio, ConfigMap, hostname, recursos menores e imagem fixada por digest;
- `prod`: duas réplicas, recursos maiores, ConfigMap, distribuição entre nós, PodDisruptionBudget e imagem fixada por digest.

**Decisão:** não foi adicionado HPA. Uma API quase ociosa e sem teste de carga não fornece base para limiares úteis; HPA aqui seria configuração ornamental. Da mesma forma, NetworkPolicy foi evitada na base porque seu comportamento depende do CNI e poderia quebrar probes/Ingress em clusters do avaliador. O isolamento de namespace e o PSS entregam proteção portátil; uma política de rede deve ser adicionada quando o CNI e os fluxos forem conhecidos.

## 5. CI/CD

O workflow é acionado em push e pull request para `main` e separa três responsabilidades. O primeiro job restaura o cache do `pip`, instala e audita o lockfile com verificação de hashes, executa testes, checa sintaxe, renderiza os overlays e valida os recursos com kubeconform em modo estrito. O segundo constrói a imagem, inicia o container como UID 10001, filesystem somente leitura, sem capabilities e com `no-new-privileges`, valida `/healthz`, `/info`, configuração e identidade efetiva e bloqueia vulnerabilidades `HIGH` ou `CRITICAL` corrigíveis com Trivy. Apenas depois desses gates, e somente em push, o terceiro job autentica no GHCR e publica `main` e `sha-<commit>`.

Permissões são mínimas: leitura de conteúdo globalmente e `packages: write` apenas no job de publicação. O checkout não persiste credenciais Git. Concorrência cancela execuções obsoletas da mesma referência. SBOM e provenance são gerados pelo BuildKit para melhorar rastreabilidade da cadeia de suprimentos. Em pushes, a imagem publicada também é exportada como artefato com retenção de um dia. Todas as actions e a imagem do kubeconform são fixadas por SHA/digest; o Dependabot mantém essas referências atualizáveis por pull requests.

**Trade-off:** a imagem é construída duas vezes, uma para o teste de runtime e outra para publicação, porque jobs não compartilham o daemon Docker. O cache do GitHub reduz o custo, enquanto a separação mantém permissões de escrita fora do job que executa o container e impede publicar algo antes do teste. Para este projeto pequeno, segurança e clareza compensam os segundos adicionais.

## 6. Observabilidade e operação

Os logs de acesso e lifecycle do Gunicorn são enviados para stdout/stderr, adequados ao coletor do cluster. Health check, versão, ambiente e hostname simplificam diagnóstico. Não foram adicionados Prometheus, tracing ou dashboards: para este serviço, isso ultrapassaria o escopo; em produção, logs JSON e métricas de latência, taxa de erros e saturação seriam o próximo passo.

## 7. Validação executada

A validação final foi executada localmente, no GitHub Actions e em um cluster k3s real.

### Validação local e CI

- 5/5 testes passaram pelo test client do Flask, cobrindo funções, endpoints, headers e erro 404 JSON;
- oito dependências diretas/transitivas foram instaladas exclusivamente pelo lockfile com hashes;
- compilação de `app/` e `tests/` sem erros;
- overlays `dev` e `prod` renderizados com Kustomize;
- 13/13 recursos renderizados foram aceitos pelo kubeconform em modo estrito contra schemas Kubernetes 1.36;
- o container iniciou no CI com as mesmas restrições essenciais do pod e respondeu corretamente aos dois endpoints;
- `pip-audit` não encontrou vulnerabilidades conhecidas nas dependências declaradas;
- Trivy não encontrou vulnerabilidades `HIGH` ou `CRITICAL` corrigíveis na imagem final;
- workflow GitHub Actions concluído com os três jobs aprovados;
- imagem publicada como `main` e `sha-<commit>`, com SBOM e provenance;
- acesso anônimo ao manifesto OCI confirmado, sem credenciais;
- digest auditado fixado nos overlays `dev` e `prod`;
- Secret Scanning, Push Protection e atualizações de segurança do Dependabot foram habilitados no repositório.

Execuções do pipeline: <https://github.com/JustShinobi/infra-platform-api/actions/workflows/ci.yml>

### Validação no k3s real

A imagem pública foi baixada diretamente do GHCR e implantada, sem pull secret nem importação manual, em um cluster k3s real. Resultados:

- namespace aceito com Pod Security Standard `restricted`;
- rollout concluído, pod `1/1 Ready`, zero reinícios;
- readiness e liveness responderam continuamente com HTTP 200;
- Service ClusterIP respondeu `/healthz` com `{"status":"ok"}`;
- `/info` retornou o SHA completo, ambiente, mensagem do ConfigMap e hostname do pod;
- imagem efetiva do containerd correspondeu ao digest público promovido;
- processo confirmado como `uid=10001 gid=10001`;
- master e worker Gunicorn confirmados em execução com `gthread`, `/dev/shm` e control socket desabilitado;
- tentativa de escrita em `/` falhou com `Read-only file system`, confirmando o controle de runtime;
- logs finais não apresentaram erros, exceptions ou tracebacks.

O primeiro rollout Flask havia identificado que o heartbeat padrão do Gunicorn precisava de um diretório temporário gravável e que o control socket tentava criar um arquivo no filesystem raiz. A configuração usa `/dev/shm` para o heartbeat e desabilita o socket não utilizado. O novo smoke test do pipeline reproduz as restrições que revelaram esse problema, prevenindo regressão sem enfraquecer `readOnlyRootFilesystem`.

O Ingress do laboratório apresentou uma limitação de reconciliação no controller compartilhado após um rollout, enquanto Service → Pod, probes e aplicação permaneceram em HTTP 200. O controller não foi reiniciado para evitar impacto em outros workloads. O overlay temporário usado nessa validação foi removido da entrega, pois não faz parte do enunciado e continha detalhes específicos da infraestrutura.

## 8. Publicação e atendimento ao enunciado

O repositório está público em <https://github.com/JustShinobi/infra-platform-api>. A imagem está pública em `ghcr.io/justshinobi/infra-platform-api`, foi verificada anonimamente e possui tags `main` e `sha-<commit>`. Assim, tanto o código quanto o artefato podem ser avaliados sem credenciais.

O pacote privado criado durante o desenvolvimento não é referenciado pela solução final. Foi adotado um nome de pacote novo para que a publicação pública ficasse claramente separada do artefato temporário, sem excluir histórico nem relaxar controles durante o desenvolvimento.

## 9. Melhorias futuras proporcionais

- assinatura da imagem com Cosign e policy de verificação;
- NetworkPolicy alinhada ao CNI do destino;
- TLS e DNS reais no Ingress;
- métricas RED e alertas baseados em SLO;
- promoção GitOps das tags imutáveis entre ambientes.

Esses itens não foram implementados porque exigem decisões do ambiente de destino ou adicionariam operação desnecessária ao projeto.
