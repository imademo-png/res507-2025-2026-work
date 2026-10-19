# Lab 42 — Verification

## Environnement
- k3s : v1.36.5+k3s1 (runtime containerd 2.3.4-k3s1.36)
- Ubuntu : 26.04.1 LTS
- Node : devops-vm, 2 CPU, ~3.3 Gi RAM

## Health check

In-cluster (DNS du Service, via le Pod busybox `service-check`) :
```
$ kubectl exec service-check -- wget -qO- http://quote-app/health
{"ok":true}
```

Port-forward :
```
$ kubectl port-forward svc/quote-app 8080:80
Forwarding from 127.0.0.1:8080 -> 3000
Handling connection for 8080
```

## 3 replicas Ready
```
NAME                         READY   STATUS    RESTARTS   AGE
quote-app-69fbbcff49-8kq6h   1/1     Running   0          20m
quote-app-69fbbcff49-kmljc   1/1     Running   0          62s
quote-app-69fbbcff49-vzv2c   1/1     Running   0          62s
```

## Remplacement d'un Pod
Supprimé : `quote-app-69fbbcff49-vzv2c` → recréé par le ReplicaSet : `quote-app-69fbbcff49-ntnpr`
```
quote-app-69fbbcff49-8kq6h   1/1     Running   0          22m
quote-app-69fbbcff49-kmljc   1/1     Running   0          3m5s
quote-app-69fbbcff49-ntnpr   1/1     Running   0          74s
```

## Readiness failure (probe sur /does-not-exist)
```
NAME                         READY   STATUS    RESTARTS   AGE
quote-app-57b88c776b-zh99d   0/1     Running   0          2m57s
quote-app-69fbbcff49-8kq6h   1/1     Running   0          27m
quote-app-69fbbcff49-kmljc   1/1     Running   0          7m40s
quote-app-69fbbcff49-ntnpr   1/1     Running   0          5m49s

NAME                   DESIRED   CURRENT   READY
quote-app-57b88c776b   1         1         0
quote-app-69fbbcff49   3         3         3
```
Event :
```
Warning  Unhealthy  (x25 over 4m27s)  kubelet  Readiness probe failed: HTTP probe failed with statuscode: 404
```
EndpointSlice : `quote-app-57b88c776b-zh99d` → `ready: false` ; les 3 Pods `69fbbcff49` → `ready: true`

- **Symptôme :** nouveau Pod en 0/1 (Running, 0 restart), rollout bloqué à 1/3, les anciens Pods continuent de servir
- **Cause :** readinessProbe sur `/does-not-exist`, route inexistante → HTTP 404
- **Fix :** remettre `path: /health` (renvoie 200) → le Pod redevient éligible, rollout terminé

## Recovery
```
$ kubectl rollout status deployment/quote-app --timeout=120s
deployment "quote-app" successfully rolled out

quote-app-69fbbcff49-8kq6h   1/1     Running   0          31m
quote-app-69fbbcff49-kmljc   1/1     Running   0          12m
quote-app-69fbbcff49-ntnpr   1/1     Running   0          10m

$ kubectl exec service-check -- wget -qO- http://quote-app/health
{"ok":true}
```

## Extension — Resources requests/limits

Manifest (`deployment.yaml`) :
```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 250m
    memory: 256Mi
```

Appliqué aux Pods (rolling update → nouveau hash `7d6744749f`, QoS `Burstable`) :
```
quote-app-7d6744749f-254c8   1/1     Running   0
quote-app-7d6744749f-6drbl   1/1     Running   0
quote-app-7d6744749f-vzrwc   1/1     Running   0
```

Réservé sur le node :
```
Namespace    Name                        CPU Req  CPU Lim  Mem Req  Mem Lim
kube-system  coredns-...                 100m     0        70Mi     170Mi
kube-system  metrics-server-...          100m     0        70Mi     0
quote-lab    quote-app-7d6744749f-254c8  100m     250m     128Mi    256Mi
quote-lab    quote-app-7d6744749f-6drbl  100m     250m     128Mi    256Mi
quote-lab    quote-app-7d6744749f-vzrwc  100m     250m     128Mi    256Mi

Allocated: cpu 500m (25%) / limits 750m — memory 524Mi (15%) / limits 938Mi
```
→ 300m / 384Mi pour l'app + 200m / 140Mi pour les Pods système k3s.

Scheduling refusé (`too-big.yaml`, request `cpu: 50` sur un node à 2 CPU) :
```
too-big   0/1   Pending   Node: <none>   PodScheduled: False
Warning  FailedScheduling  default-scheduler  0/1 nodes are available: 1 Insufficient cpu.
```

OOMKilled (`memory-test.yaml`, Pod Node.js jetable, limit 128Mi, buffers remplis et conservés) :
```
memory-test   1/1     Running            0             5s
memory-test   0/1     OOMKilled          0             5s
memory-test   1/1     Running            1 (1s ago)    5s
memory-test   0/1     OOMKilled          1 (4s ago)    8s
memory-test   0/1     CrashLoopBackOff   1 (11s ago)   19s

lastState.terminated: TODO (OOMKilled 137)
logs --previous: TODO (dernières lignes "XX MiB allocated")
```
Pendant le test, les 3 Pods `quote-app` restent 1/1 avec 0 restart.

- **Request :** ressource réservée, utilisée par le scheduler pour placer le Pod. S'il n'y a pas assez de place → Pending.
- **Limit :** plafond à l'exécution. CPU dépassé → ralenti (throttling). Mémoire dépassée → container tué par le noyau (OOMKilled, exit 137).
- **Protection du cluster :** sans limit, `memory-test` aurait consommé toute la RAM de la VM et fait tomber k3s et l'app. Avec limit, seul lui est tué.
- **Ce que ça démontre :** les requests contrôlent le placement, les limits isolent un container défaillant du reste du node.

