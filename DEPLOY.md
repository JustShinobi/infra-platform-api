# Implantação no Kubernetes

Este guia usa o ambiente `dev` nos exemplos. O overlay `prod` segue o mesmo processo, com réplicas, recursos e controles adequados ao ambiente de produção.

## Antes de começar

Você vai precisar de:

- Git e `curl` instalados;
- um cluster Kubernetes 1.27 ou mais recente, acessível pelo `kubectl`;
- Kustomize disponível pelo comando `kubectl kustomize`;
- o binário standalone do Kustomize apenas para usar o comando de promoção de imagem;
- Traefik instalado e uma `IngressClass` chamada `traefik`;
- acesso à imagem pública `ghcr.io/justshinobi/infra-platform-api`.

Quando uma mudança em `app/`, no Dockerfile ou nas dependências de runtime chega à `main`, o pipeline publica as tags `main` e `sha-<commit>` e abre um PR para promover o digest gerado nos dois overlays. A imagem fica fixada pelo digest, portanto uma alteração de tag no registry não muda o artefato implantado.

## 1. Obter o projeto

```bash
git clone https://github.com/JustShinobi/infra-platform-api.git
cd infra-platform-api
```

## 2. Conferir as mudanças

Crie o namespace antes do primeiro `diff`, renderize os manifestos e confira o que será alterado no cluster:

```bash
kubectl apply -f k8s/overlays/dev/namespace.yaml
kubectl kustomize k8s/overlays/dev
kubectl diff -k k8s/overlays/dev
```

O `kubectl diff` retorna código 0 quando não há alterações e código 1 quando encontra diferenças. Códigos maiores que 1 indicam erro.

## 3. Implantar em desenvolvimento

```bash
kubectl apply -k k8s/overlays/dev
kubectl rollout status deployment/infra-platform-api -n infra-platform-dev --timeout=120s
kubectl get pods,service,ingress -n infra-platform-dev
```

## 4. Testar a aplicação

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

## 5. Implantar em produção

O overlay `prod` usa namespace próprio, duas réplicas, recursos maiores, distribuição entre nós e PodDisruptionBudget:

```bash
kubectl apply -f k8s/overlays/prod/namespace.yaml
kubectl diff -k k8s/overlays/prod
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

O digest promovido identifica o commit que alterou a aplicação ou seu runtime. O merge do PR de promoção modifica apenas os overlays e, por isso, não publica outra imagem nem cria um ciclo de novos PRs. A tag mutável `main` serve como referência conveniente; o deploy continua usando o artefato imutável revisado no PR.

Os ConfigMaps recebem um sufixo calculado pelo Kustomize. Quando seu conteúdo muda, a referência no Deployment também muda e o Kubernetes inicia um rollout automaticamente.

## 6. Usar outra classe de Ingress ou domínio

Se o cluster usa outro nome de classe ou outro controller, crie um patch no overlay para alterar `spec.ingressClassName` e, se necessário, as anotações específicas do controller. Faça o mesmo com `spec.rules[].host` para usar outro domínio. Assim, a base continua compartilhada e não precisa ser copiada. O patch do overlay `dev` serve como referência.

## 7. Remover um ambiente

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
