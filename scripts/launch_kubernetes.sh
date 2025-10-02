pushd "$(dirname "${BASH_SOURCE[0]}")"; proj_dir=`pwd`; popd

#--------------------------------------------------------------------------------
# Deploy a publicly accessible TOM (Target and Observation Manager)
#
# This script is safe to rerun (idempotent): each execution moves the
# system toward the desired state without requiring a clean slate.
#
# Idempotent scripts, in theory, should be easier to debug and
# develop, because it isn't necessary to start from a completely fresh
# state each time they are run. If you decide to run this script
# end-to-end and run into a problem, read the comments close to where
# the problem occurred. Those comments may help lead you to a
# solution. After solving one issue, you should be able to simply
# rerun the script from the beginning.
#
# To that end, these options enable some useful output and cause the
# script to fail more quickly in the event of an error. This prevents
# the script from continuing too far, allowing the user to debug the
# problem and rerun the script from the beginning.
# --------------------------------------------------------------------------------

set -o pipefail # A command composed of piped commands is considered
                # to have failed if any of its piped commands have
                # failed.

set -e          # Exit immediately if a command fails.

set -u          # When interpolating (substituting into a string) a variable,
                # if that variable is unset, the command performing the
                # substitution is considered to have failed.

set -x          # Print each command as it is being executed.

#--------------------------------------------------------------------------------
# configuration (requires: gcloud, kubectl, helm, docker)
#--------------------------------------------------------------------------------

. "${proj_dir}/common_config.sh"

# Deployment/domain configuration (REQUIRED)
#
# This should be set to the fully qualified domain name (FQDN) on
# which the TOM should be accessible. (A fully qualified domain name
# includes the domain after the hostname. For example, the fully
# qualified domain name of a host named `www` might be
# `www.google.com`.
#
# This FQDN should be the same name that points to the TOM's static IP
# address when following along in deployment.md.
tom_hostname=${tom_hostname:-}
if [ -z "$tom_hostname" ]; then
  echo "ERROR: tom_hostname is required. Set it in the environment or scripts/common_config.sh" >&2
  exit 1
fi

# cert-manager email (REQUIRED)
# 
# This email should be used when interacting with letsencrypt.org. It
# should be a valid email that administrators on that site can use to
# contact you if they have questions about your requests.
certmanager_email=${certmanager_email:-}
if [ -z "$certmanager_email" ]; then
  echo "ERROR: certmanager_email is required. Set it in the environment or scripts/common_config.sh" >&2
  exit 1
fi

#--------------------------------------------------------------------------------
# Orchestration overview: Helm renders and applies Kubernetes manifests
# ("charts"). Kubernetes schedules pods, exposes Services, and manages
# storage. Below we add chart repositories for the CloudNativePG operator
# (Postgres orchestration) and the NGINX Ingress Controller (public
# routing/TLS).
#--------------------------------------------------------------------------------

# CloudNativePG operator chart repo (required as a dependency)
if ! helm repo list | cut -f 1 | grep -q '^cnpg$'; then
    echo "OK. cnpg repo for helm not installed. installing"
    helm repo add cnpg https://cloudnative-pg.github.io/charts
fi

if ! helm repo list | cut -f 1 | grep ingress-nginx; then
    echo "OK. nginx repo for helm not installed. installing"
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
fi

helm upgrade --install cnpg-operator cnpg/cloudnative-pg -n cnpg-system --create-namespace --wait

#--------------------------------------------------------------------------------
# Install cert-manager (for automatic Let's Encrypt certificates)
#--------------------------------------------------------------------------------

if ! helm repo list | cut -f 1 | grep -q jetstack; then
    echo "OK. jetstack repo for helm not installed. installing"
    helm repo add jetstack https://charts.jetstack.io
fi
helm repo update

if ! kubectl get namespace cert-manager >/dev/null 2>/dev/null; then
    kubectl create namespace cert-manager
fi

helm upgrade --install cert-manager jetstack/cert-manager \
     -n cert-manager \
     --set crds.enabled=true \
     --wait

#--------------------------------------------------------------------------------
# Next, build the Docker image and push it to a Google Compute Project
# repository. A repsitory is simply a container within an artifact
# registry, which can be used for storing many different kinds of
# objects encoding computer programs, in this case a docker
# container. Other repositories include places to store Python, Java,
# and Javascript packages.
# --------------------------------------------------------------------------------

# First, configure docker to push to the registry host. This will
# modify your docker configuration, but docker commands that only
# operate on local objects, like `docker build`, will not be
# affected. This is so we can run `docker push` below and push to a
# container repository that Kubernetes pods will later use to pull
# their images from.
gcloud auth configure-docker "${registry_host}"

# Idempotently create the repository.
if ! gcloud artifacts repositories describe --location "$location" "$image_repo" >/dev/null 2>/dev/null; then
    echo Creating repo "$image_repo"
    gcloud artifacts repositories create "$image_repo" \
           --repository-format=docker \
           --location "$location" \
           --description "TOM images"
fi

# Now idempotently build and push the image.
if docker manifest inspect "$image" >/dev/null 2>/dev/null; then
    echo "OK. image exists. continuing."
else
    echo "Building docker image"
    docker build --build-arg TOM_NAME="$tom_name" -t "$image" .
    docker push "$image"
fi

#--------------------------------------------------------------------------------
# Next, we'll create a static IP address for the demo TOM. This IP
# address is the one that an end-user will navigate to in order to
# actually access the TOM UI!
# --------------------------------------------------------------------------------

# First, idempotently create the compute address, which will create
# the static IP address. Be careful here: the region of this object
# should match the region of the Kubernetes cluster in order to ensure
# that it can be properly used by the object.
if ! gcloud compute addresses describe "$tom_static_ip_name" --region "$location"; then
    gcloud compute addresses create "$tom_static_ip_name" --region "$location"
fi
static_external_ip=$(gcloud compute addresses describe "$tom_static_ip_name" --region "$location" --format='get(address)')
echo got static external IP "$static_external_ip"

chart_dir="$(dirname "${proj_dir}")"

#--------------------------------------------------------------------------------
# Now wire up the actual ingress using the ingress-nginx from the
# ingress-nginx repository we installed above. The objects created by
# ingress-nginx can be shared among multiple Kubernetes objects. The
# nginx instance created in the tom-demo chart will use this resource
# in order to create a TLS interface to the service.
# --------------------------------------------------------------------------------

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx        \
     -n "${kubernetes_namespace}-ingress-nginx"                         \
     --create-namespace                                                 \
     --set controller.ingressClassResource.name=nginx-ingress-private   \
     --set controller.ingressClass=nginx-ingress-private                \
     --set controller.service.type=LoadBalancer                         \
     --set controller.service.externalTrafficPolicy=Local               \
     --set controller.service.loadBalancerIP="$static_external_ip"      \
     --wait

#--------------------------------------------------------------------------------
# Now install our own helm chart, which involves building it, creating
# some secrets, and finally installing it.
# --------------------------------------------------------------------------------

# Idempotently create the kubernetes namespace.
if ! kubectl get namespace "${kubernetes_namespace}" >/dev/null 2>/dev/null; then
    kubectl create namespace "${kubernetes_namespace}"
fi

# Build the chart.
helm dependency build "${chart_dir}/helm-chart"

# Turn off echo for this section
{ set +x; } 2>/dev/null

# Ensure the application DB Secret exists.
if ! kubectl -n "$kubernetes_namespace" get secret tom-app-db >/dev/null 2>/dev/null; then
  if [ -n "${APP_DB_PASSWORD:-}" ]; then
    APP_PW="${APP_DB_PASSWORD}"
  else
    if command -v openssl >/dev/null 2>&1; then
      APP_PW="$(openssl rand -base64 32)"
    else
      APP_PW="$(head -c 32 /dev/urandom | base64)"
    fi
  fi
  kubectl -n "$kubernetes_namespace" create secret generic tom-app-db \
    --from-literal=username=app \
    --from-literal=dbname=app \
    --from-literal=password="${APP_PW}"
  unset APP_PW
fi

# Turn echo back on
set -x

# Create a placeholder
if ! kubectl -n "$kubernetes_namespace" get secret tom-demo-secrets 2>/dev/null >/dev/null; then
    kubectl -n "$kubernetes_namespace" create secret generic tom-demo-secrets --from-literal=placeholder=1
fi

if [[ "$letsencrypt_env" == staging ]]; then
    acme_hostname=acme-staging-v02.api
    certmanager_issuer_name=letsencrypt-staging
elif [[ "$letsencrypt_env" == prod ]]; then
    acme_hostname=acme-v02.api
    certmanager_issuer_name=letsencrypt
else 
    echo unrecognized letsyncrypt environment: "$letsencrypt_env"
fi

# Install the TOM helm chart!
helm upgrade --install tom "${chart_dir}/helm-chart"                                     \
     -n "$kubernetes_namespace"                                                          \
     --create-namespace                                                                  \
     -f helm-chart/values-dev.yaml                                                       \
     --set djangoDebug="TRUE"                                                            \
     --set useWhitenoise="1"                                                             \
     --set wsgiModule="${tom_name}.wsgi"                                                 \
     --set nameOverride="$(echo ${tom_name} | tr '[A-Z]' '[a-z]')"                       \
     --set image.repository="$image_full_name"                                           \
     --set image.tag="$image_tag"                                                        \
     --set ingress.tls[0].secretName=tom-tls                                             \
     --set ingress.hosts[0].host="$tom_hostname"                                         \
     --set ingress.tls[0].hosts[0]="$tom_hostname"                                       \
     --set csrf_trusted_origins[0]="https://${tom_hostname}"                             \
     --set database.existingSecret=${database_secret_name:-tom-app-db}                   \
     --set allowedHosts[0]="$tom_hostname"                                               \
     --set-string 'ingress.annotations.nginx\.ingress\.kubernetes\.io/ssl-redirect=true' \
     --set certManager.enabled=true                                                      \
     --set certManager.issuerKind=ClusterIssuer                                          \
     --set certManager.issuerName="$certmanager_issuer_name"                             \
     --set certManager.email="$certmanager_email"                                        \
     --set certManager.acmeServer="https://${acme_hostname}.letsencrypt.org/directory"   \
     --set certManager.http01.ingressClass=nginx-ingress-private                         \
     --set image.pullPolicy=Always                                                       \
     --wait
