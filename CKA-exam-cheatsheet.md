# CKA — Complete Revision Sheet

> Target: CKA (Certified Kubernetes Administrator), current curriculum.
> Format: 2 hours, ~15–20 performance-based tasks, multiple clusters, 66% to pass.
> Everything below is written to be *typed*, not read. Prefer imperative commands over YAML whenever possible.

---

## Table of contents

1. [Exam environment & setup](#1-exam-environment--setup)
2. [kubectl fundamentals](#2-kubectl-fundamentals)
3. [Cluster architecture, installation & configuration (25%)](#3-cluster-architecture-installation--configuration-25)
4. [Workloads & scheduling (15%)](#4-workloads--scheduling-15)
5. [Services & networking (20%)](#5-services--networking-20)
6. [Storage (10%)](#6-storage-10)
7. [Troubleshooting (30%)](#7-troubleshooting-30)
8. [Security: RBAC, ServiceAccounts, SecurityContext](#8-security-rbac-serviceaccounts-securitycontext)
9. [Helm & Kustomize](#9-helm--kustomize)
10. [YAML templates to memorize](#10-yaml-templates-to-memorize)
11. [JSONPath, custom-columns, sorting](#11-jsonpath-custom-columns-sorting)
12. [Common traps & time savers](#12-common-traps--time-savers)

---

## 1. Exam environment & setup

### Domain weights

| Domain | Weight |
|---|---|
| Troubleshooting | 30% |
| Cluster Architecture, Installation & Configuration | 25% |
| Services & Networking | 20% |
| Workloads & Scheduling | 15% |
| Storage | 10% |

### First 60 seconds of the exam

```bash
alias k=kubectl
export do="--dry-run=client -o yaml"
export now="--force --grace-period=0"
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
```

`~/.vimrc` (do it once, it pays for itself):

```vim
set expandtab
set tabstop=2
set shiftwidth=2
set number
" paste toggle if indentation gets mangled
set pastetoggle=<F2>
```

### Context switching — DO THIS EVERY TASK

Every question gives you a context command. **Copy-paste it. Every single time.**

```bash
kubectl config use-context <ctx>
kubectl config get-contexts
kubectl config current-context
kubectl config set-context --current --namespace=<ns>   # saves typing -n
```

### SSH to nodes

Many tasks require working on a node:

```bash
ssh node01
sudo -i          # you will need root for /etc/kubernetes, systemctl, crictl
exit             # ALWAYS return to the base terminal before the next question
```

### Allowed docs

`kubernetes.io/docs`, `kubernetes.io/blog`, `helm.sh/docs`, and the relevant CNCF project docs (e.g. Gateway API). One extra browser tab only. Practice searching the docs fast — bookmark nothing, the browser is fresh.

Fast doc lookups that matter: "Network Policies" (has copy-paste examples), "Ingress", "Persistent Volumes", "Taints and Tolerations", "Configure Service Accounts", "Assign Pods to Nodes".

---

## 2. kubectl fundamentals

### Imperative generation (your main weapon)

```bash
k run nginx --image=nginx $do > pod.yaml
k run nginx --image=nginx --port=80 --restart=Never --rm -it -- /bin/sh
k create deploy web --image=nginx --replicas=3 $do > deploy.yaml
k create job pi --image=perl -- perl -Mbignum=bpi -wle 'print bpi(2000)'
k create cronjob hello --image=busybox --schedule="*/1 * * * *" -- /bin/sh -c 'date'
k create ns dev
k create configmap app-cfg --from-literal=KEY=value --from-file=./cfg.properties
k create secret generic db --from-literal=password=s3cr3t
k create secret docker-registry regcred --docker-server=... --docker-username=... --docker-password=...
k create service clusterip mysvc --tcp=80:8080
k expose deploy web --port=80 --target-port=8080 --name=web-svc --type=NodePort
k create ingress web --rule="app.com/*=web-svc:80"
k create sa builder
k create role dev --verb=get,list,watch --resource=pods
k create rolebinding dev-rb --role=dev --serviceaccount=default:builder
k create clusterrole viewer --verb=get,list --resource=pods,deployments
k create clusterrolebinding v-rb --clusterrole=viewer --user=jane
k create quota myquota --hard=cpu=1,memory=1G,pods=2
k create pdb mypdb --selector=app=web --min-available=2
```

Flags worth knowing on `k run`:

```bash
--command -- <cmd> <args>     # overrides entrypoint
--env=VAR=value
--labels=app=web,tier=front
--annotations=key=value
--restart=Never               # Pod (default is already Pod for run)
--dry-run=client -o yaml
--overrides='{"spec":{"nodeName":"node01"}}'
```

### Editing & patching

```bash
k edit pod nginx                      # some fields are immutable -> saved to /tmp/kubectl-edit-xxx.yaml
k replace -f pod.yaml --force         # delete + recreate, the fix for immutable fields
k patch deploy web -p '{"spec":{"replicas":5}}'
k patch deploy web --type=json -p='[{"op":"replace","path":"/spec/replicas","value":5}]'
k set image deploy/web nginx=nginx:1.27
k set resources deploy web -c=nginx --limits=cpu=200m,memory=512Mi
k set serviceaccount deploy web mysa
k scale deploy web --replicas=5
k annotate pod nginx description="test"
k label pod nginx env=prod --overwrite
```

### Inspection

```bash
k get po -A -o wide
k get po --show-labels
k get po -l 'env in (prod,dev),tier!=db'
k get all -n kube-system
k get po --field-selector status.phase=Running,spec.nodeName=node01
k get events --sort-by=.metadata.creationTimestamp -A
k describe po nginx
k logs pod -c container --previous --since=1h --tail=50 -f
k logs -l app=web --all-containers=true
k exec -it pod -c container -- sh
k cp pod:/path/file ./file -c container
k api-resources | grep -i networkpol
k api-versions
k explain pod.spec.containers.livenessProbe --recursive
k diff -f manifest.yaml
```

`kubectl explain` is the offline documentation. `--recursive` prints the full field tree — use it when you forget a nested field name.

### Deleting

```bash
k delete po nginx --force --grace-period=0
k delete -f file.yaml
k delete po -l app=web
k delete all --all -n dev
```

---

## 3. Cluster architecture, installation & configuration (25%)

### Control plane components

| Component | Role | Where |
|---|---|---|
| kube-apiserver | Front door, only component talking to etcd | static pod `/etc/kubernetes/manifests/kube-apiserver.yaml` |
| etcd | Key-value store, all cluster state | static pod `etcd.yaml`, data in `/var/lib/etcd` |
| kube-scheduler | Assigns pods to nodes | static pod `kube-scheduler.yaml` |
| kube-controller-manager | Reconciliation loops (node, replicaset, endpoints...) | static pod `kube-controller-manager.yaml` |
| kubelet | Node agent, systemd service | `systemctl status kubelet`, config `/var/lib/kubelet/config.yaml` |
| kube-proxy | Service networking (iptables/ipvs) | DaemonSet in kube-system |
| CNI plugin | Pod networking | DaemonSet, config `/etc/cni/net.d/` |

Key paths:

```
/etc/kubernetes/manifests/          static pod manifests (control plane)
/etc/kubernetes/pki/                certificates
/etc/kubernetes/admin.conf          cluster-admin kubeconfig
/etc/kubernetes/kubelet.conf        kubelet kubeconfig
/var/lib/kubelet/config.yaml        kubelet config (staticPodPath, cgroupDriver, clusterDNS)
/var/lib/etcd                       etcd data dir
/var/log/pods, /var/log/containers  container logs on node
```

### Building a cluster with kubeadm

```bash
# on all nodes: container runtime + kubeadm/kubelet/kubectl already installed in exam
kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=<IP>

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# install a CNI (e.g. Calico / Flannel) from the docs URL given in the task
kubectl apply -f <cni-manifest>

# join token
kubeadm token create --print-join-command
kubeadm token list
```

On the worker:

```bash
kubeadm join <ip>:6443 --token <tok> --discovery-token-ca-cert-hash sha256:<hash>
```

Reset a broken node: `kubeadm reset -f && rm -rf /etc/cni/net.d ~/.kube`

### Upgrading a cluster (very likely task)

**Control plane node first:**

```bash
# 1. Repo must point at the NEW minor version (classic exam trap)
vim /etc/apt/sources.list.d/kubernetes.list
#   https://pkgs.k8s.io/core:/stable:/v1.34/deb/   <- change v1.33 -> v1.34
apt update

apt-cache madison kubeadm            # find exact version string

# 2. kubeadm
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.34.0-1.1
apt-mark hold kubeadm
kubeadm version

# 3. plan & apply
kubeadm upgrade plan
kubeadm upgrade apply v1.34.0

# 4. drain, upgrade kubelet/kubectl, restart, uncordon
kubectl drain <cp-node> --ignore-daemonsets
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.34.0-1.1 kubectl=1.34.0-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
kubectl uncordon <cp-node>
```

**Worker nodes:** identical, except step 3 is `kubeadm upgrade node` (no `plan`, no `apply`).

Drain flags you will need:

```bash
kubectl drain node01 --ignore-daemonsets --delete-emptydir-data --force
kubectl cordon node01        # mark unschedulable only
kubectl uncordon node01
```

- `--ignore-daemonsets`: DaemonSet pods can't be evicted, always needed.
- `--delete-emptydir-data`: needed if pods use emptyDir.
- `--force`: needed for bare pods not managed by a controller.

### etcd backup & restore (near-certain task)

```bash
export ETCDCTL_API=3    # harmless on etcd 3.5+

etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/etcd-backup.db

etcdctl snapshot status /opt/etcd-backup.db -w table
```

Find the right cert paths from the static pod if unsure:

```bash
grep -E "cert-file|key-file|trusted-ca-file|listen-client-urls|data-dir" /etc/kubernetes/manifests/etcd.yaml
```

**Restore:**

```bash
etcdutl snapshot restore /opt/etcd-backup.db --data-dir=/var/lib/etcd-restore
# older etcd: etcdctl snapshot restore ... (deprecated but still works)

# point etcd at the new data dir
vim /etc/kubernetes/manifests/etcd.yaml
#   volumes: hostPath.path: /var/lib/etcd  ->  /var/lib/etcd-restore
#   (keep the mountPath /var/lib/etcd inside the container, OR change both consistently)

chown -R etcd:etcd /var/lib/etcd-restore   # if a non-root etcd user exists
```

Then wait — kubelet re-creates the static pod automatically. Watch with:

```bash
crictl ps | grep etcd
kubectl get po -n kube-system
```

If the API server doesn't come back, restart kubelet: `systemctl restart kubelet`.

Notes:
- Restore is **offline**: you can also `mv /etc/kubernetes/manifests/*.yaml /tmp/` to stop the control plane, restore, then move them back.
- `--initial-cluster`, `--initial-advertise-peer-urls`, `--name` are only needed for multi-node etcd.

### Certificates

```bash
kubeadm certs check-expiration
kubeadm certs renew all
kubeadm certs renew apiserver

openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A2 Validity
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A1 "Subject Alternative Name"
```

After renewing control plane certs, restart the static pods (move manifests out and back, or `crictl rm` the containers).

### CertificateSigningRequest (user onboarding)

```bash
openssl genrsa -out jane.key 2048
openssl req -new -key jane.key -out jane.csr -subj "/CN=jane/O=dev"
cat jane.csr | base64 -w 0
```

```yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: jane
spec:
  request: <base64-of-csr>
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
```

```bash
kubectl get csr
kubectl certificate approve jane
kubectl certificate deny jane
kubectl get csr jane -o jsonpath='{.status.certificate}' | base64 -d > jane.crt

kubectl config set-credentials jane --client-key=jane.key --client-certificate=jane.crt --embed-certs=true
kubectl config set-context jane-ctx --cluster=kubernetes --user=jane
kubectl config use-context jane-ctx
```

`-w 0` on base64 is essential — newlines break the request.

### Node management

```bash
kubectl get nodes -o wide
kubectl describe node node01 | grep -A10 Conditions
kubectl taint node node01 key=value:NoSchedule
kubectl delete node node01        # after kubeadm reset on that node
```

### CRDs and operators

```bash
kubectl get crd
kubectl api-resources --api-group=<group>
kubectl explain <kind> --api-version=<group>/<version>
kubectl get <customresource> -A
```

Minimal CRD shape (know it exists, rarely written by hand in the exam):

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.stable.example.com      # must be <plural>.<group>
spec:
  group: stable.example.com
  scope: Namespaced                      # or Cluster
  names:
    plural: backups
    singular: backup
    kind: Backup
    shortNames: [bk]
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              replicas: {type: integer}
```

---

## 4. Workloads & scheduling (15%)

### Deployments and rollouts

```bash
k rollout status deploy/web
k rollout history deploy/web
k rollout history deploy/web --revision=2
k rollout undo deploy/web
k rollout undo deploy/web --to-revision=2
k rollout restart deploy/web
k rollout pause deploy/web ; k rollout resume deploy/web
```

Strategy:

```yaml
spec:
  strategy:
    type: RollingUpdate        # or Recreate
    rollingUpdate:
      maxSurge: 25%            # extra pods allowed above desired
      maxUnavailable: 25%      # pods that may be down
  revisionHistoryLimit: 10
  minReadySeconds: 10
```

### Workload types quick map

- **Deployment** → stateless, ReplicaSet-backed, rolling updates.
- **StatefulSet** → stable network IDs (`web-0`, `web-1`), ordered create/delete, per-pod PVC via `volumeClaimTemplates`, requires a headless Service (`clusterIP: None`).
- **DaemonSet** → one pod per node; add tolerations to run on control-plane nodes.
- **Job** → `completions`, `parallelism`, `backoffLimit`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished`, `completionMode: Indexed`.
- **CronJob** → `schedule`, `concurrencyPolicy: Allow|Forbid|Replace`, `startingDeadlineSeconds`, `successfulJobsHistoryLimit`, `suspend: true`.

Cron format: `minute hour day-of-month month day-of-week` (`*/5 * * * *` = every 5 min).

### ConfigMaps & Secrets

```yaml
    env:
    - name: SINGLE
      valueFrom:
        configMapKeyRef: {name: app-cfg, key: KEY}
    - name: PASS
      valueFrom:
        secretKeyRef: {name: db, key: password}
    envFrom:
    - configMapRef: {name: app-cfg}
    - secretRef: {name: db}
    volumeMounts:
    - name: cfg
      mountPath: /etc/config
      readOnly: true
  volumes:
  - name: cfg
    configMap:
      name: app-cfg
      items:
      - key: cfg.properties
        path: app.properties
      defaultMode: 0644
  - name: sec
    secret:
      secretName: db
```

```bash
k get secret db -o jsonpath='{.data.password}' | base64 -d
echo -n 's3cr3t' | base64
```

Immutable config: `immutable: true` in the ConfigMap/Secret.

### Resources, requests, limits

```yaml
    resources:
      requests: {cpu: "100m", memory: "128Mi"}
      limits:   {cpu: "500m", memory: "512Mi"}
```

- QoS: **Guaranteed** (requests == limits for all containers), **Burstable** (some requests set), **BestEffort** (nothing set).
- Memory limit exceeded → OOMKilled. CPU limit exceeded → throttled, not killed.
- `LimitRange` sets defaults per namespace; `ResourceQuota` caps namespace totals (if a quota on cpu/memory exists, every pod **must** declare requests/limits).

### Probes

```yaml
    livenessProbe:            # restart container on failure
      httpGet: {path: /healthz, port: 8080}
      initialDelaySeconds: 10
      periodSeconds: 5
      timeoutSeconds: 1
      failureThreshold: 3
    readinessProbe:           # remove from Service endpoints on failure
      exec: {command: ["cat", "/tmp/ready"]}
    startupProbe:             # disables the other two until it succeeds
      tcpSocket: {port: 8080}
      failureThreshold: 30
      periodSeconds: 10
```

### Init & sidecar containers

```yaml
spec:
  initContainers:
  - name: wait-db
    image: busybox
    command: ['sh','-c','until nslookup db; do sleep 2; done']
  - name: logshipper            # native sidecar
    image: fluentd
    restartPolicy: Always       # <- this makes it a sidecar, runs alongside main containers
```

### Scheduling: nodeSelector / affinity / taints

```yaml
  nodeName: node01          # bypasses the scheduler entirely
  nodeSelector:
    disktype: ssd
```

```yaml
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: disktype
            operator: In            # In, NotIn, Exists, DoesNotExist, Gt, Lt
            values: ["ssd"]
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - {key: zone, operator: In, values: ["eu-west-1a"]}
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels: {app: web}
        topologyKey: kubernetes.io/hostname
```

Taints & tolerations:

```bash
k taint node node01 app=blue:NoSchedule
k taint node node01 app=blue:NoSchedule-        # remove (trailing dash)
k describe node node01 | grep -i taint
```

```yaml
  tolerations:
  - key: "app"
    operator: "Equal"        # or "Exists" (omit value)
    value: "blue"
    effect: "NoSchedule"     # NoSchedule | PreferNoSchedule | NoExecute
    tolerationSeconds: 3600  # NoExecute only
```

Control-plane taint: `node-role.kubernetes.io/control-plane:NoSchedule`.

**Taints repel pods from nodes; affinity attracts pods to nodes.** Neither alone guarantees exclusivity — combine both.

Topology spread:

```yaml
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule    # or ScheduleAnyway
    labelSelector:
      matchLabels: {app: web}
```

Priority & preemption:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: {name: high}
value: 1000000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
---
# in pod spec:
  priorityClassName: high
```

### Static pods

Drop a manifest in `/etc/kubernetes/manifests/` on a node; kubelet runs it and creates a mirror pod named `<pod>-<nodename>`.

```bash
grep staticPodPath /var/lib/kubelet/config.yaml
k run static-web --image=nginx $do > /etc/kubernetes/manifests/static-web.yaml
rm /etc/kubernetes/manifests/static-web.yaml     # the ONLY way to delete it
```

You cannot delete a static pod with `kubectl delete` — it comes straight back.

### Autoscaling

```bash
k autoscale deploy web --min=2 --max=10 --cpu-percent=70
k get hpa
k top nodes ; k top pods --containers
```

HPA requires **metrics-server** running. If `kubectl top` errors, metrics-server is missing or its TLS is broken (`--kubelet-insecure-tls`).

---

## 5. Services & networking (20%)

### Service types

| Type | Behaviour |
|---|---|
| ClusterIP | Internal virtual IP (default) |
| NodePort | ClusterIP + port on every node, range **30000–32767** |
| LoadBalancer | NodePort + external LB (cloud) |
| ExternalName | CNAME to an external DNS name, no proxying |
| Headless (`clusterIP: None`) | No VIP, DNS returns pod IPs directly — used by StatefulSets |

```yaml
apiVersion: v1
kind: Service
metadata: {name: web-svc}
spec:
  type: NodePort
  selector: {app: web}
  ports:
  - name: http
    port: 80           # service port
    targetPort: 8080   # container port (can be a named port)
    nodePort: 30080
    protocol: TCP
```

Debugging a Service = checking that the selector matches pod labels:

```bash
k get svc web-svc -o wide
k get endpoints web-svc          # EMPTY endpoints = selector mismatch or pods not Ready
k get endpointslices -l kubernetes.io/service-name=web-svc
k describe svc web-svc
```

### DNS

- Service: `<svc>.<ns>.svc.cluster.local`
- Headless pod: `<pod-name>.<svc>.<ns>.svc.cluster.local`
- Pod (rare): `<ip-with-dashes>.<ns>.pod.cluster.local`

```bash
k run tmp --image=busybox:1.28 --rm -it --restart=Never -- nslookup web-svc.default
k run tmp --image=nicolaka/netshoot --rm -it -- bash
k exec pod -- cat /etc/resolv.conf
k get cm coredns -n kube-system -o yaml
k -n kube-system logs -l k8s-app=kube-dns
k get svc -n kube-system kube-dns
```

Use `busybox:1.28` — newer busybox has a broken `nslookup` for cluster DNS.

Custom pod DNS:

```yaml
  dnsPolicy: ClusterFirst      # Default | ClusterFirst | ClusterFirstWithHostNet | None
  hostNetwork: true            # then you need ClusterFirstWithHostNet for cluster DNS
```

### Ingress

```bash
k create ingress web --class=nginx \
  --rule="app.example.com/api*=api-svc:80" \
  --rule="app.example.com/*=web-svc:80" $do
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix        # Prefix | Exact | ImplementationSpecific
        backend:
          service:
            name: api-svc
            port:
              number: 80
  tls:
  - hosts: [app.example.com]
    secretName: tls-secret
```

TLS secret: `k create secret tls tls-secret --cert=tls.crt --key=tls.key`

### Gateway API (newer curriculum item)

Objects: **GatewayClass** (cluster-scoped, infra provider) → **Gateway** (listeners/ports) → **HTTPRoute** (routing rules).

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: web-gw}
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces: {from: Same}     # Same | All | Selector
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: web-route}
spec:
  parentRefs:
  - name: web-gw
  hostnames: ["app.example.com"]
  rules:
  - matches:
    - path: {type: PathPrefix, value: /api}
    backendRefs:
    - name: api-svc
      port: 80
      weight: 100
```

```bash
k get gatewayclass,gateway,httproute -A
k describe httproute web-route      # check the "Accepted"/"ResolvedRefs" conditions
```

### NetworkPolicy

Rules to burn into memory:

- Policies are **additive** and **allow-only** (no deny rules).
- A pod with *no* policy selecting it = all traffic allowed.
- A pod selected by *any* policy = only explicitly allowed traffic for the listed `policyTypes`.
- `podSelector: {}` selects **all pods** in the namespace.
- Within one rule element, `namespaceSelector` + `podSelector` in the **same list item** = AND. As **separate list items** = OR. This is the classic trap.

Default deny all ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny, namespace: prod}
spec:
  podSelector: {}
  policyTypes: [Ingress]
```

Full example:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
  namespace: prod
spec:
  podSelector:
    matchLabels: {app: api}
  policyTypes: [Ingress, Egress]
  ingress:
  - from:
    - podSelector:
        matchLabels: {app: web}          # AND with the namespaceSelector below
      namespaceSelector:
        matchLabels: {kubernetes.io/metadata.name: front}
    - ipBlock:
        cidr: 10.0.0.0/16
        except: [10.0.5.0/24]            # OR (separate list item)
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels: {app: db}
    ports:
    - {protocol: TCP, port: 5432}
  - to:                                   # don't forget DNS egress!
    - namespaceSelector: {}
      podSelector:
        matchLabels: {k8s-app: kube-dns}
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
```

Every namespace has the built-in label `kubernetes.io/metadata.name: <ns>` — use it instead of labelling namespaces yourself.

Testing:

```bash
k exec -it tester -- wget -qO- --timeout=2 http://api-svc:8080
k exec -it tester -- nc -zv api-svc 8080
```

### CNI

```bash
ls /etc/cni/net.d/                 # active CNI config, lowest-numbered file wins
ls /opt/cni/bin/                   # plugin binaries
k get po -n kube-system -o wide    # CNI DaemonSet health
```

If nodes are `NotReady` with `network plugin is not ready: cni config uninitialized`, the CNI is missing or crashed.

### kube-proxy

```bash
k get ds -n kube-system kube-proxy
k logs -n kube-system -l k8s-app=kube-proxy
iptables-save | grep <service-name>
ipvsadm -Ln          # if mode=ipvs
```

---

## 6. Storage (10%)

### Volume types you should recognize

`emptyDir` (pod lifetime, `medium: Memory` for tmpfs), `hostPath` (node path, types `Directory`, `DirectoryOrCreate`, `File`, `Socket`), `configMap`, `secret`, `projected`, `downwardAPI`, `persistentVolumeClaim`, CSI.

### PV / PVC

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-log
spec:
  capacity: {storage: 1Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain     # Retain | Delete | Recycle(deprecated)
  storageClassName: manual
  hostPath: {path: /mnt/data}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: pvc-log}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources:
    requests: {storage: 500Mi}
```

Access modes:
- `ReadWriteOnce` (RWO) — one **node**
- `ReadOnlyMany` (ROX)
- `ReadWriteMany` (RWX)
- `ReadWriteOncePod` (RWOP) — one **pod**

Binding rules: a PVC binds to a PV with **≥ requested capacity**, **matching accessModes**, **matching storageClassName**. Mismatched `storageClassName` is the #1 reason a PVC stays `Pending`.

Mounting in a pod:

```yaml
    volumeMounts:
    - name: data
      mountPath: /var/log/app
      subPath: app                  # mount a subdirectory only
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: pvc-log
```

### StorageClass & dynamic provisioning

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/no-provisioner      # or a CSI driver
volumeBindingMode: WaitForFirstConsumer        # or Immediate
reclaimPolicy: Delete
allowVolumeExpansion: true
parameters:
  type: gp3
```

`WaitForFirstConsumer` delays binding until a pod is scheduled — a PVC sitting in `Pending` with this mode is **normal** until a pod consumes it.

### Expansion

Requires `allowVolumeExpansion: true`. Then just edit the PVC's `spec.resources.requests.storage` upward (shrinking is not allowed).

```bash
k edit pvc pvc-log
k get pvc pvc-log -o jsonpath='{.status.capacity.storage}'
```

### Useful commands

```bash
k get pv,pvc -A
k get sc
k describe pvc pvc-log           # Events tell you exactly why it's Pending
k get pv pv-log -o jsonpath='{.spec.claimRef}'
```

A `Released` PV won't rebind: clear `spec.claimRef` (`k patch pv pv-log -p '{"spec":{"claimRef":null}}'`).

---

## 7. Troubleshooting (30%)

This is the biggest domain. Work top-down: **cluster → node → control plane → workload → networking**.

### Pod not starting — decision tree

| Status | Likely cause | Check |
|---|---|---|
| `Pending` | No node fits: resources, taints, affinity, unbound PVC | `k describe po` → Events |
| `ContainerCreating` | Image pull, volume mount, CNI failure | `k describe po`, kubelet logs |
| `ImagePullBackOff` / `ErrImagePull` | Wrong image name/tag, no registry secret | `k describe po` |
| `CrashLoopBackOff` | App exits or fails probe | `k logs po --previous` |
| `OOMKilled` | Memory limit too low | `k describe po` → Last State |
| `Error` / `Completed` | Command finished/failed | `k logs` |
| `Terminating` (stuck) | Finalizers, node gone | `k delete --force --grace-period=0` |
| `Init:0/1` | Init container blocked | `k logs po -c <init>` |

```bash
k describe po <pod> | tail -30
k logs <pod> --previous
k get events -n <ns> --sort-by=.lastTimestamp
k get po <pod> -o yaml | grep -A5 -i state
```

### Ephemeral debug containers

```bash
k debug -it <pod> --image=busybox --target=<container>     # attach to running pod's namespaces
k debug <pod> -it --image=ubuntu --share-processes --copy-to=debug-pod
k debug node/node01 -it --image=busybox                    # host filesystem at /host
```

### Node not Ready

```bash
k get nodes
k describe node node01           # Conditions: MemoryPressure, DiskPressure, PIDPressure, Ready

ssh node01
systemctl status kubelet
journalctl -u kubelet -f
journalctl -u kubelet --since "10 min ago" --no-pager | tail -50
systemctl restart kubelet
systemctl enable --now kubelet

# runtime
systemctl status containerd
crictl ps -a
crictl logs <container-id>
crictl images
crictl pods

df -h ; free -m ; top            # disk full / OOM at node level
```

Common node failures:
- kubelet service stopped or not enabled
- wrong `--kubeconfig` / expired cert in `/etc/kubernetes/kubelet.conf`
- wrong apiserver address in `/etc/kubernetes/kubelet.conf` (`server: https://...:6443`)
- cgroup driver mismatch between kubelet (`/var/lib/kubelet/config.yaml`) and containerd (`/etc/containerd/config.toml`) — both should be `systemd`
- swap enabled (`swapoff -a`) on older versions
- disk pressure → evicted pods

### Control plane down

If `kubectl` itself fails ("connection refused to 6443"):

```bash
ssh <control-plane>
crictl ps -a | grep -E "apiserver|etcd|scheduler|controller"
crictl logs <id>
ls /var/log/pods/
cat /var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log | tail -50

# YAML typo in a static pod manifest is the classic exam scenario
cat /etc/kubernetes/manifests/kube-apiserver.yaml
journalctl -u kubelet | grep -i apiserver
```

Things to verify in `kube-apiserver.yaml`: `--etcd-servers`, cert paths, `--service-cluster-ip-range`, `--advertise-address`, port, container image tag, volume `hostPath`s that must exist.

After editing a static pod manifest, kubelet reloads it automatically within seconds. If nothing happens: `systemctl restart kubelet`.

A scheduler that is down = pods stuck in `Pending` with **no events**. A controller-manager that is down = Deployments create no ReplicaSets/pods.

### Service / networking troubleshooting

```bash
k get svc,ep -n <ns>
k describe svc <svc>                            # check Selector vs pod labels
k get po -l <selector> --show-labels
k run t --image=nicolaka/netshoot --rm -it -- bash
  curl -v http://svc.ns.svc.cluster.local
  nslookup svc.ns
  nc -zv 10.96.0.1 443
k get netpol -A                                 # a policy may be silently blocking you
```

Checklist: pod Ready? labels match selector? `targetPort` == container port? Endpoints populated? NetworkPolicy blocking? kube-proxy running? DNS resolving?

### Application logs and metrics

```bash
k logs deploy/web --all-containers --tail=100
k logs -f -l app=web --max-log-requests=10
k top po -A --sort-by=memory
k top no
```

### Cluster-level sanity checks

```bash
k get --raw='/readyz?verbose'
k get --raw='/healthz'
k cluster-info
k get componentstatuses          # deprecated but still shown
k get po -n kube-system
```

---

## 8. Security: RBAC, ServiceAccounts, SecurityContext

### RBAC objects

- **Role / RoleBinding** → namespaced.
- **ClusterRole / ClusterRoleBinding** → cluster-wide.
- **ClusterRole + RoleBinding** → grant cluster-role permissions inside **one** namespace (very common exam pattern).

```bash
k create role pod-reader --verb=get,list,watch --resource=pods -n dev
k create rolebinding pod-reader-b --role=pod-reader --serviceaccount=dev:builder -n dev
k create clusterrole pv-reader --verb=get,list --resource=persistentvolumes
k create clusterrolebinding pv-reader-b --clusterrole=pv-reader --user=jane
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: pod-reader, namespace: dev}
rules:
- apiGroups: [""]                # "" = core group
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["create", "update", "patch", "delete"]
  resourceNames: ["web"]         # optional, restricts to named objects
```

Verbs: `get list watch create update patch delete deletecollection`. Wildcard `*`.

Verification (do this on every RBAC task):

```bash
k auth can-i create deploy --as=jane -n dev
k auth can-i list pods --as=system:serviceaccount:dev:builder -n dev
k auth can-i --list --as=jane -n dev
k auth whoami
```

### ServiceAccounts

```bash
k create sa builder -n dev
k set serviceaccount deploy web builder
```

```yaml
spec:
  serviceAccountName: builder
  automountServiceAccountToken: false
```

Since 1.24 no Secret token is auto-created. To get one:

```bash
k create token builder -n dev --duration=1h
```

Or a long-lived token Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: builder-token
  annotations:
    kubernetes.io/service-account.name: builder
type: kubernetes.io/service-account-token
```

### SecurityContext

```yaml
spec:
  securityContext:                # pod-level
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    runAsNonRoot: true
  containers:
  - name: app
    securityContext:              # container-level, overrides pod-level
      runAsUser: 2000
      allowPrivilegeEscalation: false
      privileged: false
      readOnlyRootFilesystem: true
      capabilities:
        add: ["NET_ADMIN", "SYS_TIME"]
        drop: ["ALL"]
```

Capabilities are **container-level only** — putting them at pod level is invalid YAML for the API.

### Pod Security Admission

Namespace labels:

```bash
k label ns dev \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
```

Levels: `privileged`, `baseline`, `restricted`. Modes: `enforce`, `audit`, `warn`.

---

## 9. Helm & Kustomize

### Helm

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm repo list
helm search repo nginx --versions
helm show values bitnami/nginx > values.yaml
helm show chart bitnami/nginx

helm install myrel bitnami/nginx -n web --create-namespace
helm install myrel bitnami/nginx -f values.yaml --set replicaCount=3 --version 15.0.0
helm upgrade myrel bitnami/nginx --set image.tag=1.27 --reuse-values
helm upgrade --install myrel bitnami/nginx      # idempotent

helm list -A
helm list -A --all              # includes failed/uninstalled
helm status myrel -n web
helm get values myrel -n web
helm get manifest myrel -n web
helm history myrel -n web
helm rollback myrel 1 -n web
helm uninstall myrel -n web

helm template myrel bitnami/nginx     # render locally, no cluster write
helm install myrel chart/ --dry-run --debug
helm pull bitnami/nginx --untar
```

Chart layout: `Chart.yaml`, `values.yaml`, `templates/`, `charts/`, `_helpers.tpl`.

### Kustomize

`kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: prod
namePrefix: prod-
nameSuffix: -v1

labels:
- pairs:
    env: prod
  includeSelectors: false

commonAnnotations:
  owner: platform

resources:
- deployment.yaml
- service.yaml
- ../../base

images:
- name: nginx
  newName: nginx
  newTag: 1.27

replicas:
- name: web
  count: 5

configMapGenerator:
- name: app-cfg
  literals:
  - KEY=value
  files:
  - app.properties

secretGenerator:
- name: db
  literals:
  - password=s3cr3t

generatorOptions:
  disableNameSuffixHash: true

patches:
- path: patch-resources.yaml
  target:
    kind: Deployment
    name: web
- patch: |-
    - op: replace
      path: /spec/replicas
      value: 4
  target:
    kind: Deployment
    name: web
```

```bash
kubectl kustomize ./overlays/prod            # render to stdout
kubectl apply -k ./overlays/prod
kubectl delete -k ./overlays/prod
kubectl diff -k ./overlays/prod
```

Base + overlay layout:

```
base/            kustomization.yaml, deployment.yaml, service.yaml
overlays/dev/    kustomization.yaml (resources: ../../base) + patches
overlays/prod/   kustomization.yaml + patches
```

---

## 10. YAML templates to memorize

### Minimal pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels: {app: web}
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
    command: ["sh", "-c"]
    args: ["sleep 3600"]
  restartPolicy: Always        # Always | OnFailure | Never
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels: {app: web}
spec:
  replicas: 3
  selector:
    matchLabels: {app: web}      # MUST match template labels
  template:
    metadata:
      labels: {app: web}
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
```

### DaemonSet (no `replicas`)

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: agent}
spec:
  selector:
    matchLabels: {app: agent}
  template:
    metadata:
      labels: {app: agent}
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: agent
        image: busybox
        command: ["sh","-c","sleep 1d"]
```

Trick: generate a Deployment with `$do`, change `kind` to `DaemonSet`, delete `replicas`, `strategy` and `status`.

### StatefulSet

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: web}
spec:
  serviceName: web-headless
  replicas: 3
  selector:
    matchLabels: {app: web}
  template:
    metadata:
      labels: {app: web}
    spec:
      containers:
      - name: nginx
        image: nginx
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata: {name: data}
    spec:
      accessModes: [ReadWriteOnce]
      storageClassName: fast
      resources:
        requests: {storage: 1Gi}
```

### Job / CronJob

```yaml
apiVersion: batch/v1
kind: Job
metadata: {name: pi}
spec:
  completions: 5
  parallelism: 2
  backoffLimit: 4
  activeDeadlineSeconds: 300
  ttlSecondsAfterFinished: 100
  template:
    spec:
      restartPolicy: Never      # required: Never or OnFailure
      containers:
      - name: pi
        image: perl
        command: ["perl","-Mbignum=bpi","-wle","print bpi(200)"]
---
apiVersion: batch/v1
kind: CronJob
metadata: {name: hello}
spec:
  schedule: "*/5 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: hello
            image: busybox
            command: ["sh","-c","date; echo hi"]
```

---

## 11. JSONPath, custom-columns, sorting

```bash
# single field
k get po nginx -o jsonpath='{.metadata.name}{"\n"}'

# all images in the cluster
k get po -A -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u

# name + nodeName pairs
k get po -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}'

# filter by expression
k get po -o jsonpath='{.items[?(@.spec.nodeName=="node01")].metadata.name}'

# node internal IPs
k get no -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'

# custom columns
k get po -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase
k get pv -o custom-columns=NAME:.metadata.name,CAP:.spec.capacity.storage --sort-by=.spec.capacity.storage

# sorting
k get po --sort-by=.metadata.creationTimestamp
k get no --sort-by=.status.capacity.cpu
k get events --sort-by=.metadata.creationTimestamp

# decode a secret
k get secret db -o jsonpath='{.data.password}' | base64 -d
```

Typical exam phrasing: *"write the names of ... to /opt/answer.txt"* — always redirect with `>` and `cat` the file afterwards to confirm.

---

## 12. Common traps & time savers

### Traps

1. **Forgetting the context switch.** You will silently solve a task in the wrong cluster.
2. **Namespace.** Most tasks specify one. `-n <ns>` or set it on the context.
3. **Deployment selector must equal template labels** — otherwise the API rejects it.
4. **Immutable fields** (e.g. `spec.selector`, a pod's containers): `k replace --force -f`.
5. **NodePort range** is 30000–32767.
6. **`targetPort` vs `port`** on Services.
7. **Empty endpoints** = selector/label mismatch or pods not Ready.
8. **PVC Pending** = storageClassName mismatch, size, accessMode, or `WaitForFirstConsumer` (normal).
9. **NetworkPolicy**: forgetting egress to kube-dns on UDP/TCP 53 breaks everything.
10. **`namespaceSelector` + `podSelector` in the same list item = AND.**
11. **Static pods** cannot be deleted with kubectl — remove the manifest file.
12. **Repo version** must be bumped before `apt install kubeadm=<new>` during upgrades.
13. **`--ignore-daemonsets`** is basically always required on drain.
14. **base64 `-w 0`** to avoid line wrapping.
15. **Capabilities go on the container**, not the pod, securityContext.
16. **`kubectl edit`** on a rejected change writes to `/tmp/kubectl-edit-*.yaml` — reuse that file instead of retyping.
17. **crictl, not docker**, on modern nodes. `crictl` needs root.
18. **Exit the SSH session** before the next question.

### Time savers

- Use `$do` and pipe to a file, then edit — never write YAML from scratch.
- `k explain <res> --recursive | less` beats searching docs for a field name.
- Flag hard questions and move on; each question shows its weight — do the high-percentage ones first.
- Never delete a resource you can `edit`, unless the field is immutable.
- Verify everything: after every change run `k get` / `k describe` / `curl` to confirm.
- For "which node/pod..." questions, write the answer to the requested file immediately.
- `watch k get po` (or `k get po -w`) while a rollout or restore converges.

### Verification snippets

```bash
# is the pod actually on the intended node?
k get po -o wide

# is the deployment healthy?
k rollout status deploy/web --timeout=60s

# does the service work?
k run t --image=busybox:1.28 --rm -it --restart=Never -- wget -qO- --timeout=3 web-svc

# did the RBAC change take effect?
k auth can-i <verb> <res> --as=system:serviceaccount:<ns>:<sa> -n <ns>

# is etcd healthy after restore?
k get po -n kube-system && k get no
```

---

## Final 5-minute checklist before starting

- [ ] aliases + `$do` + completion exported
- [ ] vim indentation configured
- [ ] read each question fully, note the context line
- [ ] confirm namespace per task
- [ ] keep a scratch file for answers (`/tmp/notes`)
- [ ] don't leave a question half-done; either finish or revert cleanly

Good luck.
