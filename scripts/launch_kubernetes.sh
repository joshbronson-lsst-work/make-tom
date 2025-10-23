pushd "$(dirname "${BASH_SOURCE[0]}")"; proj_dir=`pwd`; popd

set -euxo pipefail

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| configuration (requires: gcloud or aws, kubectl, helm, docker)"
echo "|--------------------------------------------------------------------------------"
set -x

. "${proj_dir}/common_config.sh"

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| tom_hostname: Deployment/domain configuration (REQUIRED)"
echo "|" 
echo "| This should be set to the fully qualified domain name (FQDN) on"
echo "| which the TOM should be accessible. (A fully qualified domain name"
echo "| includes the domain after the hostname. For example, the fully"
echo "| qualified domain name of a host named \"www\" might be"
echo "| \"www.google.com\"."
echo "|"
echo "| This FQDN should be the same name that points to the TOM's static IP"
echo "| address when following along in deployment.md."
echo "|--------------------------------------------------------------------------------"
set -x

tom_hostname=${tom_hostname:-}

if [ -z "$tom_hostname" ]; then
  { set +x; } 2>/dev/null
  echo "|ERROR: tom_hostname is required. Set it in the environment or scripts/common_config.sh" >&2
  set -x
  exit 1
fi

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| certmanager_email: cert-manager email (REQUIRED)"
echo "| "
echo "| This email should be used when interacting with letsencrypt.org. It"
echo "| should be a valid email that administrators on that site can use to"
echo "| contact you if they have questions about your requests."
echo "|--------------------------------------------------------------------------------"
set -x
certmanager_email=${certmanager_email:-}
if [ -z "$certmanager_email" ]; then
  echo "|ERROR: certmanager_email is required. Set it in the environment or scripts/common_config.sh" >&2
  exit 1
fi

if [[ "$platform" == "EKS" ]]; then
    { set +x; } 2>/dev/null
    echo "|--------------------------------------------------------------------------------"
    echo "| Updating Kubernetes to connect to cluster $cluster_name"
    echo "|--------------------------------------------------------------------------------"
    set -x
    aws eks update-kubeconfig --region "$region" --name "$cluster_name"
fi

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Orchestration overview: Helm renders and applies Kubernetes manifests"
echo "| (\"charts\"). Kubernetes schedules pods, exposes Services, and manages"
echo "| storage. Below we add chart repositories for the CloudNativePG operator"
echo "| (Postgres orchestration) and the NGINX Ingress Controller (public"
echo "| routing/TLS)."
echo "|--------------------------------------------------------------------------------"
set -x

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| AWS load balancer chart repo (required as a dependency)"
echo "|--------------------------------------------------------------------------------"
set -x

helm repo add eks 'https://aws.github.io/eks-charts'

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| CloudNativePG operator chart repo (required as a dependency)"
echo "|--------------------------------------------------------------------------------"
set -x

helm repo add cnpg 'https://cloudnative-pg.github.io/charts'

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| nginx ingress chart repo (required as a dependency)"
echo "|--------------------------------------------------------------------------------"
set -x

helm repo add ingress-nginx 'https://kubernetes.github.io/ingress-nginx'

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| jetstack repo for cert-manager (required as a dependency)"
echo "|--------------------------------------------------------------------------------"
set -x

helm repo add jetstack 'https://charts.jetstack.io'

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| pull in changes, if any, to helm repos"
echo "|--------------------------------------------------------------------------------"
set -x

helm repo update

if [[ "$platform" == "EKS" ]]; then
    { set +x; } 2>/dev/null
    echo "|--------------------------------------------------------------------------------"
    echo "| install aws-load-balancer helm chart so nginx can serve as aws load balancer"
    echo "|--------------------------------------------------------------------------------"
    set -x

    VPC_ID=$(aws eks describe-cluster --name "$cluster_name" --region "$region" --query 'cluster.resourcesVpcConfig.vpcId' --output text)
    helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
        --set clusterName="$cluster_name" \
        --set region="$region" \
        --set vpcId="$VPC_ID" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller \
        --wait --timeout 5m
fi

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| install cloud-native postgres helm chart"
echo "|--------------------------------------------------------------------------------"
set -x

helm upgrade --install cnpg-operator cnpg/cloudnative-pg        \
     -n cnpg-system                                             \
     --create-namespace                                         \
     --wait

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Install cert-manager (for automatic Let's Encrypt certificates)"
echo "|--------------------------------------------------------------------------------"
set -x

helm upgrade --install cert-manager jetstack/cert-manager       \
     -n cert-manager                                            \
     --set crds.enabled=true                                    \
     --create-namespace                                         \
     --wait

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Next, build the Docker image and push it to a Google Compute Project"
echo "| repository. A repsitory is simply a container within an artifact"
echo "| registry, which can be used for storing many different kinds of"
echo "| objects encoding computer programs, in this case a docker"
echo "| container. Other repositories include places to store Python, Java,"
echo "| and Javascript packages."
echo "| --------------------------------------------------------------------------------"
set -x

{ set +x; } 2>/dev/null
echo "| --------------------------------------------------------------------------------"
echo "| First, configure docker to push to the registry host. This will"
echo "| modify your docker configuration, but docker commands that only"
echo "| operate on local objects, like \"docker build\", will not be"
echo "| affected. This is so we can run \"docker push\" below and push to a"
echo "| container repository that Kubernetes pods will later use to pull"
echo "| their images from."
echo "| --------------------------------------------------------------------------------"
set -x

if [[ "$platform" == "EKS" ]]; then
    if aws ecr describe-repositories --repository-names "$image_repo" --region "$region" >/dev/null 2>/dev/null; then
        echo "| OK. ${image_repo} exists. continuing."
    else
        echo "| ${image_repo} does not exist. creating it."
        aws ecr create-repository \
            --repository-name "$image_repo" \
            --region "$region" | cat
    fi
    aws ecr get-login-password --region "$region" |
        docker login --username AWS --password-stdin "${account_id}.dkr.ecr.${region}.amazonaws.com"
elif [[ "$platform" == "GKE" ]]; then
    gcloud auth configure-docker "${registry_host}"
    
    { set +x; } 2>/dev/null
    echo "| Create the repository."
    set -x
    if ! gcloud artifacts repositories describe --location "$location" "$image_repo" >/dev/null 2>/dev/null; then
        { set +x; } 2>/dev/null
        echo Creating repo "$image_repo"
        set -x
        gcloud artifacts repositories create "$image_repo" \
               --repository-format=docker \
               --location "$location" \
               --description "TOM images"
    fi
else
    echo invalid platform "$platform"
    exit 1
fi

chart_dir="$(dirname "${proj_dir}")"
fingerprint=$( (
  cd .. && \
  find . -type f \
    ! -path './env/*' \
    ! -path './.venv/*' \
    ! -path './__pycache__/*' \
    ! -name '*.pyc' \
    ! -path './media/*' \
    ! -path './staticfiles/*' \
    ! -path './static/*' \
    ! -path './tmp/*' \
    ! -name 'db.sqlite3' \
    -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}'
) )
if [ ! -z "${fingerprint:-}" ]; then
  computed_tag="tom-$(echo "${tom_name}" | tr '[A-Z]' '[a-z]')-$(echo "$fingerprint" | cut -c1-12)"
  image_tag="$computed_tag"
  image="${image_full_name}:${image_tag}"
  { set +x; } 2>/dev/null
  echo "|Using content-hash image tag: ${image_tag}"
  set -x
fi

{ set +x; } 2>/dev/null
echo "| Now build and push the image for the resolved tag."
set -x
if docker manifest inspect "$image" >/dev/null 2>/dev/null; then
    { set +x; } 2>/dev/null
    echo "| OK. image ${image} already exists. Skipping build."
    set -x
else
    { set +x; } 2>/dev/null
    echo "|Building docker image ${image}"
    set -x
    pwd
    docker build --platform linux/amd64 --build-arg TOM_NAME="$tom_name" -f Dockerfile -t "$image" ..
    docker push "$image"
fi

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Next, we'll create a static IP addresses for the TOM deploy. These IP"
echo "| addresses are the ones that an end-user will navigate to in order to"
echo "| actually access the TOM UI!"
echo "| --------------------------------------------------------------------------------"
set -x

if [[ "$platform" == "EKS" ]]; then
    { set +x; } 2>/dev/null
    echo "|--------------------------------------------------------------------------------"
    echo "| In EKS, we will create one IP address for every subnet used by the cluster."
    echo "|--------------------------------------------------------------------------------"
    set -x

    readarray -t subnet_arr < <(aws ec2 describe-subnets --filters Name=vpc-id,Values="${VPC_ID}" --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId" --output text | tr '\t' '\n' | grep -v '^$')

    address_allocation_ids=()
    for subnet in "${subnet_arr[@]}"; do
        address_name="eksctl-${cluster_name}/public/${subnet}"
        address_allocation_id="$(aws ec2 describe-addresses --region "$region" --filter "Name=tag:Name,Values=${address_name}" --query "Addresses[].AllocationId" --output text | cat)"
        if [[ -z "$address_allocation_id" ]]; then
            address_allocation_id="$(aws ec2 allocate-address --region "$region" --domain vpc --query AllocationId --output text | cat)"
            aws ec2 create-tags --region "$region" --resources "$address_allocation_id" --tags "Key=Name,Value=${address_name}"
        fi

        address_allocation_ids+=("$address_allocation_id")
    done

elif [[ "$platform" == "GKE" ]]; then
    { set +x; } 2>/dev/null
    echo "| --------------------------------------------------------------------------------"
    echo "| First, create the compute address, which will create"
    echo "| the static IP address. Be careful here: the region of this object"
    echo "| should match the region of the Kubernetes cluster in order to ensure"
    echo "| that it can be properly used by the object."
    echo "| "
    echo "| Note that this is only necessary on Google Kubernetes Engine."
    echo "| --------------------------------------------------------------------------------"
    set -x
    if ! gcloud compute addresses describe "$tom_static_ip_name" --region "$location" 2>/dev/null >/dev/null; then
        gcloud compute addresses create "$tom_static_ip_name" --region "$location"
    fi
    static_external_ip=$(gcloud compute addresses describe "$tom_static_ip_name" --region "$location" --format='get(address)')

    { set +x; } 2>/dev/null
    echo got static external IP "$static_external_ip"
    set -x
fi

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Now wire up the actual ingress using the ingress-nginx from the"
echo "| ingress-nginx repository we installed above. The objects created by"
echo "| ingress-nginx can be shared among multiple Kubernetes objects. The"
echo "| nginx instance created in the tom-deploy chart will use this resource"
echo "| in order to create a TLS interface to the service."
echo "| --------------------------------------------------------------------------------"
set -x

ingress_sets=(
     --set controller.ingressClassResource.name=nginx-ingress-private
     --set controller.ingressClass=nginx-ingress-private 
     --set controller.service.type=LoadBalancer 
     --set controller.service.externalTrafficPolicy=Local 
     --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=external
     --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing
)

if [[ "$platform" == "EKS" ]]; then
    subnet_csv="$(echo -n "${subnet_arr[@]}" | jq -r -R 'split(" ") | map(select(. != "")) | join(",")')"
    address_allocation_ids_csv="$(echo -n "${address_allocation_ids[@]}" | jq -r -R 'split(" ") | map(select(. != "")) | join(",")')"

    ingress_sets=(
        "${ingress_sets[@]}"
        --set controller.kind=DaemonSet
        --set controller.service.externalTrafficPolicy=Cluster
        --set controller.config.compute-full-forwarded-for=true
        --set controller.config.use-proxy-protocol=true
        --set-string controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type"=instance
        --set-string controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-proxy-protocol"='*'
        --set-string controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-target-group-attributes"="preserve_client_ip.enabled=false,proxy_protocol_v2.enabled=true"
        --set-string controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-subnets"="${subnet_csv//,/\\,}"
        --set-string controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-eip-allocations"="${address_allocation_ids_csv//,/\\,}"
    )
elif [[ "$platform" == "GKE" ]]; then
    ingress_sets=(
        "${ingress_sets[@]}"
        --set controller.service.loadBalancerIP="$static_external_ip"
    )
else
    echo "invalid platform: $platform"
    exit 1
fi

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx        \
     -n "${kubernetes_namespace}-ingress-nginx"                         \
     --create-namespace                                                 \
     "${ingress_sets[@]}"                                               \
     --wait


{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Now install our own helm chart, which involves building it, creating"
echo "| some secrets, and finally installing it."
echo "| --------------------------------------------------------------------------------"
set -x

{ set +x; } 2>/dev/null
echo "| Idempotently create the kubernetes namespace."
set -x
if ! kubectl get namespace "${kubernetes_namespace}" >/dev/null 2>/dev/null; then
    kubectl create namespace "${kubernetes_namespace}"
fi

{ set +x; } 2>/dev/null
echo "| Build the chart."
set -x
helm dependency build "${chart_dir}/helm-chart"

{ set +x; } 2>/dev/null
echo "| Turn off echo for this section"
set -x
{ set +x; } 2>/dev/null

{ set +x; } 2>/dev/null
echo "| Ensure the application DB Secret exists."
set -x
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

{ set +x; } 2>/dev/null
echo "| Turn echo back on"
set -x
set -x

{ set +x; } 2>/dev/null
echo "| --------------------------------------------------------------------------------"
echo "| Ensure application secret with optional GCP credentials exists."
echo "| If GOOGLE_APPLICATION_CREDENTIALS_JSON is not present in the secret and gcloud is available,"
echo "| attempt to create a new service account key and store it in the secret."
echo "| --------------------------------------------------------------------------------"
set -x

if ! kubectl -n "$kubernetes_namespace" get secret tom-deploy-secrets 2>/dev/null >/dev/null; then
    kubectl -n "$kubernetes_namespace" create secret generic tom-deploy-secrets --from-literal=placeholder=1
fi

if [[ "$letsencrypt_env" == staging ]]; then
    acme_hostname=acme-staging-v02.api
    certmanager_issuer_name=letsencrypt-staging
elif [[ "$letsencrypt_env" == prod ]]; then
    acme_hostname=acme-v02.api
    certmanager_issuer_name=letsencrypt
else 
    { set +x; } 2>/dev/null
    echo unrecognized letsyncrypt environment: "$letsencrypt_env"
    set -x
fi


{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Set up access to the Google storage bucket from the django pod. This"
echo "| will allow the Django pod to manage data product binaries.a"
echo "| --------------------------------------------------------------------------------"
set -x

{ set +x; } 2>/dev/null
echo "| Create a Kubernetes service account for the django server pod."
set -x
if kubectl -n "$kubernetes_namespace" get serviceaccount "$data_product_service_account_id" >/dev/null 2>/dev/null; then
    { set +x; } 2>/dev/null
    echo OK. Service account "$data_product_service_account_id" already exists. continuing.
    set -x
else
    kubectl create -n "$kubernetes_namespace" serviceaccount "$data_product_service_account_id"
fi

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| As a final step, annotate the data service account to tell GCP that"
echo "| this service account is allowed to impersonate the GCP service"
echo "| account we created for the purpose of viewing private Google Storage"
echo "| buckets."
echo "|--------------------------------------------------------------------------------"
echo
set -x

kubectl annotate serviceaccount "$data_product_service_account_id" \
    --namespace "$kubernetes_namespace" \
    iam.gke.io/gcp-service-account="${data_product_service_account_id}@${project_id}.iam.gserviceaccount.com"

tom_sets=(
     --set djangoDebug="TRUE"                                                            \
     --set useWhitenoise="1"                                                             \
     --set wsgiModule="${tom_name}.wsgi"                                                 \
     --set nameOverride="$tom_name_lowercase"                                            \
     --set image.repository="$image_full_name"                                           \
     --set image.tag="$image_tag"                                                        \
     --set ingress.tls[0].secretName=tom-tls                                             \
     --set ingress.hosts[0].host="$tom_hostname"                                         \
     --set ingress.tls[0].hosts[0]="$tom_hostname"                                       \
     --set csrf_trusted_origins[0]="https://${tom_hostname}"                             \
     --set database.existingSecret=${database_secret_name:-tom-app-db}                   \
     --set allowedHosts[0]="$tom_hostname"                                               \
     --set serviceAccount.name="$data_product_service_account_id"                        \
     --set serviceAccount.create=false                                                   \
     --set-string 'ingress.annotations.nginx\.ingress\.kubernetes\.io/ssl-redirect=true' \
     --set certManager.enabled=true                                                      \
     --set certManager.issuerKind=ClusterIssuer                                          \
     --set certManager.issuerName="$certmanager_issuer_name"                             \
     --set certManager.email="$certmanager_email"                                        \
     --set certManager.acmeServer="https://${acme_hostname}.letsencrypt.org/directory"   \
     --set certManager.http01.ingressClass=nginx-ingress-private                         \
     --set image.pullPolicy=Always
)

if [[ "$platform" == "EKS" ]]; then
    tom_sets=(
        "${tom_sets[@]}"
        --set cnpg.storage.storageClass="auto-ebs-sc"
	--set s3BucketName="$bucket_name"
	--set s3RegionName="$region"
    )
elif [[ "$platform" == "GKE" ]]; then
    tom_sets=(
        "${tom_sets[@]}"
	--set gsBucketName="$bucket_name"
    )
else
    echo "invalid platform: $platform"
    exit 1
fi

{ set +x; } 2>/dev/null
echo "| Install the TOM helm chart!"
set -x
helm upgrade --install tom "${chart_dir}/helm-chart"    \
     -n "$kubernetes_namespace"                         \
     --create-namespace                                 \
     -f helm-chart/values-dev.yaml                      \
     --wait                                             \
     "${tom_sets[@]}"
