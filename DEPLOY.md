# Deploy no Kubernetes

## Pré-requisitos

- cluster Kubernetes 1.27+ acessível por `kubectl`;
- Kustomize embutido no `kubectl` (`kubectl kustomize`);
- binário `kustomize` standalone apenas se for usar o comando de promoção mostrado na seção 4;
- um Ingress Controller. Os overlays `dev` e `prod` assumem a classe `traefik`; ajuste `spec.ingressClassName` se usar NGINX ou outra implementação;
- acesso à imagem pública `ghcr.io/justshinobi/infra-platform-api`.

O pipeline também publica a tag identificável `sha-<commit>`. O overlay de produção fixa o digest promovido, evitando que uma alteração de tag mude o artefato implantado.

## 1. Inspecionar antes de aplicar

```bash
kubectl kustomize k8s/overlays/dev
kubectl diff -k k8s/overlays/dev
```

`kubectl diff` pode retornar código 1 quando encontra mudanças; isso é esperado.

## 2. Implantar o ambiente de desenvolvimento

```bash
kubectl apply -k k8s/overlays/dev
kubectl rollout status deployment/infra-platform-api -n infra-platform-dev --timeout=120s
kubectl get pods,service,ingress -n infra-platform-dev
```

## 3. Validar sem depender de DNS

```bash
kubectl port-forward -n infra-platform-dev service/infra-platform-api 8080:80
```

Em outro terminal:

```bash
curl http://127.0.0.1:8080/healthz
curl http://127.0.0.1:8080/info
```

Para validar o Ingress, aponte o host fictício para o IP do Ingress Controller e acesse `http://infra-platform-dev.candidato.local/info`. Sem alterar DNS, é possível testar com:

```bash
curl -H 'Host: infra-platform-dev.candidato.local' http://IP_DO_INGRESS/info
```

## 4. Trocar para produção

O overlay `prod` cria outro namespace, usa duas réplicas, recursos maiores, distribuição entre nós e PodDisruptionBudget:

```bash
kubectl apply -k k8s/overlays/prod
kubectl rollout status deployment/infra-platform-api -n infra-platform-prod --timeout=120s
```

Os overlays fixam o digest promovido. Para promover outro digest sem editar a base:

```bash
cd k8s/overlays/prod
kustomize edit set image ghcr.io/justshinobi/infra-platform-api=ghcr.io/justshinobi/infra-platform-api@sha256:DIGEST_VALIDADO
kubectl apply -k .
```

Faça commit dessa mudança para manter o estado desejado auditável.

## 5. Configurar outro Ingress Controller ou host

Crie um patch no overlay correspondente para mudar `spec.ingressClassName` e `spec.rules[].host`. A base não deve ser duplicada. Os patches de Ingress do overlay `dev` demonstram esse padrão.

## 6. Remover

```bash
kubectl delete -k k8s/overlays/dev
# ou
kubectl delete -k k8s/overlays/prod
```

Cada overlay usa um namespace próprio, evitando colisões e permitindo executar ambientes simultaneamente.

## Registry privado (opcional)

A imagem deste projeto é pública e não precisa de credencial. Se a solução for adaptada para um registry privado, crie primeiro o namespace e o ServiceAccount, depois associe o pull secret antes de aplicar o restante:

```bash
kubectl apply -f k8s/overlays/dev/namespace.yaml
kubectl apply -n infra-platform-dev -f k8s/base/serviceaccount.yaml
kubectl create secret docker-registry ghcr-pull \
  --namespace infra-platform-dev \
  --docker-server=ghcr.io \
  --docker-username=SEU_USUARIO \
  --docker-password=TOKEN_COM_READ_PACKAGES
kubectl patch serviceaccount infra-platform-api -n infra-platform-dev \
  -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}'
kubectl apply -k k8s/overlays/dev
```

Se o ServiceAccount for alterado depois da criação dos pods, execute `kubectl rollout restart deployment/infra-platform-api -n infra-platform-dev`, pois pods existentes não herdam a mudança. Nunca versione o token ou o Secret renderizado.
