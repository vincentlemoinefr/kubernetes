#!/usr/bin/env bash
# =============================================================================
# STEP 2b - The Secret (EX-06)
# =============================================================================
# EX-06 says: no password in clear text in a manifest. So the Secret is NOT
# shipped as a .yaml file - it is created imperatively, here. Nothing with a
# password in it ever touches the disk, which is also what TEST 3 checks
# (grep over *.yaml).
#
# Why not a Secret YAML with stringData? Because base64 is not encryption and
# a committed Secret manifest is a plaintext password with extra steps. In a
# real project you would use sealed-secrets, SOPS, or an external vault - the
# principle being demonstrated here is the same: the value lives outside the
# manifests, the Deployments only reference it.
#
# Usage:
#   chmod +x 02-secret.sh
#   ./02-secret.sh                       # generates random passwords
#   MYSQL_USER_PW=... ADMIN_PW=... ./02-secret.sh    # or supply your own
#
# WARNING - re-running this after MariaDB has initialised will rotate the
# passwords in Kubernetes but NOT in the database (the credentials are baked
# into the PVC on first boot). If you re-run it, pass the same values again
# through the environment variables above, or delete the PVC and start over.
# =============================================================================
set -euo pipefail

NS="cloud"
SECRET_NAME="cloud-secrets"

gen() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24; }

MYSQL_ROOT_PW="${MYSQL_ROOT_PW:-$(gen)}"
MYSQL_USER_PW="${MYSQL_USER_PW:-$(gen)}"
ADMIN_PW="${ADMIN_PW:-$(gen)}"

# --dry-run=client | kubectl apply  makes the script idempotent: it creates the
# Secret the first time and updates it afterwards, instead of failing with
# "already exists". The generated YAML only ever exists in the pipe.
kubectl create secret generic "${SECRET_NAME}" \
  --namespace "${NS}" \
  --from-literal=mysql-root-pw="${MYSQL_ROOT_PW}" \
  --from-literal=mysql-user-pw="${MYSQL_USER_PW}" \
  --from-literal=admin-pw="${ADMIN_PW}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo
echo "Secret '${SECRET_NAME}' is in place in namespace '${NS}'."
echo "Keys: mysql-root-pw, mysql-user-pw, admin-pw"
echo
echo "Write this down now - the web login is:"
echo "  user     : admin"
echo "  password : ${ADMIN_PW}"
echo
echo "To read it back later:"
echo "  kubectl get secret ${SECRET_NAME} -n ${NS} -o jsonpath='{.data.admin-pw}' | base64 -d; echo"
