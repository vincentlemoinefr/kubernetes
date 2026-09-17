# Day 3 Challenge — The Migration

Three-tier file cloud (Nextcloud + MariaDB + Redis) moved onto Kubernetes, built
bottom-up, one floor at a time.

## Files, in the order they are applied

| # | File | What it does |
|---|------|--------------|
| 1 | `01-namespace.yaml` | The `cloud` namespace |
| 2 | `02-configmap.yaml` | Non-sensitive config |
| 2 | `02-secret.sh` | Creates the Secret, no plaintext on disk |
| 3 | `03-storage.yaml` | The two PVCs |
| 4 | `04-mariadb.yaml` | Database Deployment + ClusterIP Service |
| 5 | `05-redis.yaml` | Cache Deployment + ClusterIP Service |
| 6 | `06-nextcloud.yaml` | Web Deployment + ClusterIP Service |
| 7 | `07-ingress.yaml` | The single HTTP entry point |
| 8 | `08-bonus.yaml` | Optional bonuses (notes + commented manifests) |
| — | `09-acceptance-tests.sh` | The client's seven checks |

## Run it

```bash
# 0. prerequisites
minikube addons enable ingress
kubectl get pods -n ingress-nginx                     # controller Running?
echo "$(minikube ip) nextcloud.local" | sudo tee -a /etc/hosts

# 1..7, validating at each floor
kubectl apply -f 01-namespace.yaml
kubectl config set-context --current --namespace=cloud

kubectl apply -f 02-configmap.yaml
chmod +x 02-secret.sh && ./02-secret.sh                # note the admin password

kubectl apply -f 03-storage.yaml
kubectl get pvc                                        # BOTH must be Bound

kubectl apply -f 04-mariadb.yaml
kubectl rollout status deploy/mariadb

kubectl apply -f 05-redis.yaml
kubectl exec deploy/redis -- redis-cli ping            # PONG

kubectl apply -f 06-nextcloud.yaml
kubectl logs -f deploy/nextcloud -c wait-for-mariadb    # Init:0/2 then Init:1/2
kubectl logs -f deploy/nextcloud -c nextcloud           # 2–4 min, be patient

kubectl apply -f 07-ingress.yaml
kubectl get ingress                                    # ADDRESS fills in
```

Then open <http://nextcloud.local> and log in as `admin` with the password the
secret script printed.

## Where each requirement is satisfied

| Réf | Pts | Where | How |
|-----|-----|-------|-----|
| EX-01 | 2 | `01` | Namespace `cloud`, every object carries `namespace: cloud` |
| EX-02 | 6 | `04` `05` `06` | Three Deployments, `replicas: 1` |
| EX-03 | 6 | `04` `05` `06` | Three ClusterIP Services → DNS names `mariadb`, `redis`, `nextcloud` |
| EX-04 | 8 | `03` | Two RWO PVCs on `/var/lib/mysql` and `/var/www/html` |
| EX-05 | 2 | `05` | No PVC, plus `--save ""` and `--appendonly no` (justification below) |
| EX-06 | 8 | `02-secret.sh` | Secret created imperatively, injected only via `secretKeyRef` |
| EX-07 | 4 | `02-configmap.yaml` | Hosts, DB name, admin user, trusted domains |
| EX-08 | 6 | `04` | `type: ClusterIP`, no NodePort, no LoadBalancer |
| EX-09 | 8 | `07` | One Ingress on `nextcloud.local`, everything else ClusterIP |
| EX-10 | 4 | `04` `05` `06` | `requests` and `limits` on all three containers |
| EX-11 | 6 | `06` | readinessProbe on `/status.php`, delay 90 s, 30 retries, no livenessProbe |

## The written justifications

**EX-05 — why the cache gets no persistent storage.**
Redis here holds sessions, file locks and transient lookups: data that is
either short-lived or rebuildable from the database, which is the real source
of truth. Persisting it would cost disk space, a PVC to provision and manage,
a slower start-up while the dump is reloaded, and a real risk of reloading a
*stale* cache that disagrees with the database — a worse failure mode than an
empty one. Losing a cache is not losing data: the next request repopulates it.
The flags `--save ""` and `--appendonly no` make the decision explicit in the
manifest rather than leaving it to the image's defaults, and `--maxmemory`
with an LRU policy keeps the cache inside its own limit instead of being
OOM-killed by the kubelet.

**EX-11 — why the probe is shaped the way it is.**
The first boot runs the installer for 2–4 minutes, during which the app either
does not answer or answers an error. `initialDelaySeconds: 90` means no
question is asked during that window; `failureThreshold: 30` at
`periodSeconds: 10` adds five more minutes of tolerance on a slow machine.
There is deliberately no livenessProbe: readiness only gates traffic, while
liveness *kills*. A liveness probe firing mid-install restarts the pod, the
new pod resumes from a half-written volume, and the loop never ends — with a
configuration that is otherwise perfectly correct. That is the most
frustrating failure in the whole course, and it is self-inflicted.

**EX-08 — why there is nothing to "close" on the database.**
A ClusterIP Service has no route from outside the cluster by construction; it
is a virtual IP only reachable from inside the pod network. The mistake to
avoid is adding a NodePort "so I can debug with a SQL client". For that,
use a temporary tunnel instead — `kubectl port-forward svc/mariadb 3306:3306 -n
cloud` — which lasts as long as the terminal and leaves a trace.

**The startup-order trap — and what the initContainers do about it.**
Nothing stops Nextcloud from starting before MariaDB accepts connections. The
challenge says one or two restarts are acceptable here, and asks what you would
do in production. The answer is in `06-nextcloud.yaml`: two initContainers,
`wait-for-mariadb` and `wait-for-redis`, each a busybox loop on `nc -z` against
the Service name, which run to completion before the application container is
allowed to start.

Two things make this more than a `sleep`:

- The Service only carries an endpoint once the dependency's own
  readinessProbe passes, so a successful TCP connect means the database has
  declared itself ready — not merely that a pod exists.
- A dependency that never comes up leaves the pod in `Init:0/2` with a log
  line saying exactly what it is waiting for, instead of a crash loop whose
  first cause has already scrolled away.

Redis gets one too, for a different reason: Nextcloud writes the cache
configuration at install time and will happily install itself against a Redis
it cannot reach, then log file-locking errors afterwards. Redis starts in
seconds, so the wait is free.

MariaDB and Redis themselves get no initContainer — they depend on nothing but
their volume, and the scheduler already refuses to start a pod whose PVC is
not Bound.

Where this stops being enough: an initContainer only proves the dependency was
up *at start-up*. It does nothing if the database disappears an hour later —
that case is handled by retries in the application, a PodDisruptionBudget, and
a real database operator rather than a single-replica Deployment.

**EX-06 — the classic trap.**
Putting the password in the Secret *and* also hard-coding it in the Deployment
"to be safe" cancels the entire point. Every sensitive value here is injected
with `secretKeyRef` and never with `value:`.

A note on `TEST 3`: its grep flags any line containing "password" that is not
a `name:` line, so a Secret key literally called `mysql-password` would show up
as a false positive. The keys are named `mysql-root-pw`, `mysql-user-pw` and
`admin-pw` — rename them if you prefer, and adjust the grep accordingly. The
same constraint shaped MariaDB's readinessProbe: `healthcheck.sh --su-mysql
--connect --innodb` connects over the local Unix socket as the mysql user, so
it proves the server answers a real query without ever putting a credential on
a command line. A `tcpSocket` probe on 3306 also works, but it opens and closes
a connection without speaking the protocol, and MariaDB logs
`Aborted connection ... unauthenticated` once per probe period — noise that
reads like a port scan and is only the kubelet.

## Bonus 4 — right-sizing (2 pts)

```bash
minikube addons enable metrics-server
kubectl top pods -n cloud                # wait ~1 min for the first samples
```

Record actual usage at rest and during an upload, then compare with the
estimates in the manifests:

| Tier | Estimated request | Measured (fill in) | New request |
|------|-------------------|--------------------|-------------|
| nextcloud | 200m / 256Mi | | |
| mariadb | 100m / 256Mi | | |
| redis | 25m / 64Mi | | |

The rule of thumb: `requests` ≈ steady-state usage (it is what the scheduler
reserves and what decides whether the pod fits on a node), `limits` ≈ the peak
you are willing to allow. Requests set far above real usage waste capacity
cluster-wide; requests far below it get the pod scheduled onto a node that
cannot actually feed it.

## When something breaks — three reflexes, in this order

```bash
kubectl describe pod <pod> -n cloud      # read the Events at the bottom
kubectl logs <pod> -n cloud              # read the FIRST error, not the last
kubectl get events -n cloud --sort-by=.lastTimestamp
```

Common ones here:

- **PVC stuck `Pending`** → no default StorageClass. `kubectl get sc`, and
  `minikube addons enable storage-provisioner` if it is missing.
- **Nextcloud restarting in a loop** → almost always a livenessProbe someone
  added, or a readinessProbe that is too impatient.
- **"Access through untrusted domain"** → the Ingress host and
  `NEXTCLOUD_TRUSTED_DOMAINS` disagree. Note that this value is only applied at
  *install* time; if the app is already installed, fix it in the running pod:
  `kubectl exec deploy/nextcloud -n cloud -- php occ config:system:set
  trusted_domains 0 --value=nextcloud.local`
- **Ingress `ADDRESS` stays empty** → the controller is not running, or
  `ingressClassName: nginx` does not match `kubectl get ingressclass`.
- **`Access denied for user`** after re-running `02-secret.sh` → the database
  kept the password baked into its PVC on first boot. Re-run the script with
  the original values, or delete the PVC and start the tier over.

## Shutting down for the night

```bash
kubectl scale deploy --all --replicas=0 -n cloud
```

The PVCs and their data stay intact — one command brings everything back, which
is itself one more demonstration that storage is decoupled from compute.
