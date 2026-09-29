# Implantação no Kubernetes

Este guia usa o ambiente `dev` nos exemplos. O overlay `prod` segue o mesmo processo, com réplicas, recursos e controles adequados ao ambiente de produção.

## Antes de começar

Você vai precisar de:

- um cluster Kubernetes 1.27 ou mais recente, acessível pelo `kubectl`;
- Kustomize disponível pelo comando `kubectl kustomize`;
- o binário standalone do Kustomize apenas para usar o comando de promoção de imagem;
- um Ingress Controller. Os overlays usam a classe `traefik` por padrão;
- acesso à imagem pública `ghcr.io/justshinobi/infra-platform-api`.

O pipeline publica as tags `main` e `sha-<commit>`. Nos overlays, a imagem é fixada pelo digest, portanto uma alteração de tag no registry não muda o artefato implantado.

## 1. Conferir as mudanças

Renderize os manifestos e confira o que será alterado no cluster:

```bash
kubectl kustomize k8s/overlays/dev
kubectl diff -k k8s/overlays/dev
```

O `kubectl diff` retorna código 1 quando encontra diferenças. Nesse caso, o resultado é esperado e não indica falha.

## 2. Implantar em desenvolvimento

```bash
kubectl apply -k k8s/overlays/dev
kubectl rollout status deployment/infra-platform-api -n infra-platform-dev --timeout=120s
kubectl get pods,service,ingress -n infra-platform-dev
```

## 3. Testar a aplicação

O port-forward permite validar o serviço sem depender de DNS ou do Ingress:

```bash
kubectl port-forward -n infra-platform-dev service/infra-platform-api 8080:80
```

Em outro terminal:

```bash
curl http://127.0.0.1:8080/healthz
curl http://127.0.0.1:8080/info
```

Para testar o Ingress, direcione `infra-platform-api-dev.local` para o endereço do Ingress Controller. Também é possível enviar o host diretamente na requisição:

```bash
curl -H 'Host: infra-platform-api-dev.local' http://IP_DO_INGRESS/info
```

## 4. Implantar em produção

O overlay `prod` usa namespace próprio, duas réplicas, recursos maiores, distribuição entre nós e PodDisruptionBudget:

```bash
kubectl apply -k k8s/overlays/prod
kubectl rollout status deployment/infra-platform-api -n infra-platform-prod --timeout=120s
```

Para promover uma nova imagem, atualize o digest no overlay sem alterar a base:

```bash
cd k8s/overlays/prod
kustomize edit set image ghcr.io/justshinobi/infra-platform-api=ghcr.io/justshinobi/infra-platform-api@sha256:DIGEST_VALIDADO
kubectl apply -k .
```

Inclua essa alteração no Git para manter o estado implantado rastreável.

## 5. Usar outro Ingress Controller ou domínio

Crie um patch no overlay para alterar `spec.ingressClassName` e `spec.rules[].host`. Assim, a base continua compartilhada e não precisa ser copiada. O patch do overlay `dev` serve como referência.

## 6. Remover um ambiente

```bash
kubectl delete -k k8s/overlays/dev
# ou
kubectl delete -k k8s/overlays/prod
```

Cada overlay tem seu próprio namespace, o que evita colisões e permite manter os dois ambientes ativos ao mesmo tempo.

## Se a imagem estiver em um registry privado

A imagem deste projeto é pública e não exige credenciais. Caso ela seja movida para um registry privado, crie primeiro o namespace e o ServiceAccount e associe o pull secret antes de aplicar os demais recursos:

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

Se o ServiceAccount for alterado depois da criação dos pods, reinicie o deployment para que os novos pods recebam a configuração:

```bash
kubectl rollout restart deployment/infra-platform-api -n infra-platform-dev
```

Não versione o token nem o Secret renderizado.
