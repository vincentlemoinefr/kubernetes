#!/usr/bin/env bash
# =============================================================================
# The client's acceptance run - the seven tests, in order.
# Run it yourself before handing anything in: this is the grade.
#   chmod +x 09-acceptance-tests.sh && ./09-acceptance-tests.sh
# =============================================================================
NS="cloud"
hr() { printf '\n\033[1m%s\033[0m\n' "── $* ───────────────────────────────"; }

hr "TEST 1 - everything running, nothing restart-looping"
kubectl get pods -n "$NS" -o wide
echo "Expect: 3/3 pods Running, READY 1/1, RESTARTS low and stable."

hr "TEST 2 - storage reserved (both Bound)"
kubectl get pvc -n "$NS"

hr "TEST 3 - no password in clear text in the manifests"
if grep -riE "password|motdepasse" ./*.yaml | grep -v "SecretKeyRef\|secretKeyRef\|name:"; then
  echo ">> FAIL: the lines above need to move into the Secret."
else
  echo "OK - nothing found."
fi

hr "TEST 4 - the database is not exposed (no NodePort, no LoadBalancer)"
kubectl get svc -n "$NS"
echo "Expect: TYPE ClusterIP on all three, EXTERNAL-IP <none>."

hr "TEST 5 - internal DNS works between tiers"
kubectl run t-dns -it --rm --image=busybox:1.36 --restart=Never -n "$NS" \
  -- nslookup mariadb

hr "TEST 6 - PERSISTENCE (the one that counts)"
cat <<'TXT'
Manual, and deliberately so:
  a) open http://nextcloud.local, log in as admin, create a second user
     (Settings > Users), or upload a file.
  b) kill the database pod:
        kubectl delete pod -l app=mariadb -n cloud
  c) wait for the new pod to be Ready:
        kubectl get pods -n cloud -w
  d) reload the site and log in again: the user/file must still be there.

A pod that restarts and loses the client's data is an incident.
A pod that restarts and finds everything again is the job.
TXT

hr "TEST 7 - one single entry point, by domain name"
curl -I -H "Host: nextcloud.local" "http://$(minikube ip)"
echo "Expect: HTTP/1.1 302 (redirect to /login) or 200. Not 404, not 503."

hr "Done"
