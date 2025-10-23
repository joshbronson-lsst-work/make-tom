pushd "$(dirname "${BASH_SOURCE[0]}")"; proj_dir=`pwd`; popd

#--------------------------------------------------------------------------------
# Configuration with environment overrides.
# Export any of these variables before running the launcher to override defaults.
#
# REQUIRED (set here or in your shell):
#   - tom_name            Short identifier for this TOM deployment
#   - platform            GKE (for Google Kubernetes Engine) or 
#                         EKS (Elastic Kubernetes Service)
#   - tom_hostname        Public URL (DNS hostname) you will use
#   - certmanager_email   Email used by Let's Encrypt (cert-manager)
#
# Notes:
# - "Hostname" here means the website URL, not an astronomical "Target".
# - Tools needed locally: gcloud, kubectl, helm, docker.
# - `gcloud auth login` opens a browser tab; follow the prompts.
#--------------------------------------------------------------------------------

tom_name=${tom_name:-}
if [ -z "$tom_name" ]; then
  { set +x; } 2>/dev/null
  echo "ERROR: tom_name is required. Set it in the environment or scripts/common_config.sh" >&2
  set -x
  exit 1
fi
tom_name_lowercase="$(echo ${tom_name} | tr '[A-Z]' '[a-z]')"

platform=${platform:-}
if [[ "$platform" != "EKS" && "$platform" != "GKE" ]]; then
  { set +x; } 2>/dev/null
  echo "ERROR: platform is required. Set it to EKS or GKE in the environment or scripts/common_config.sh" >&2
  set -x
  exit 1
fi

# region and zone
project_id="$(echo ${project_id:-tom-${tom_name}-project} | tr '[A-Z]' '[a-z]')"
if [[ "$platform" == "EKS" ]] ; then
    region=us-west-1
    zone=${zone:-usw1-az1}
elif [[ "$platform" == "GKE" ]]; then
    region=us-central1
    zone=${zone:-"us-central1-a"}
else
    echo "invalid platform: $platform"
    exit 1
fi

bucket_name="$(echo ${bucket_name:-tom-${tom_name}-data-products} | tr '[A-Z]' '[a-z]')"

proj_descr=${proj_descr:-"TOM Project"}
cluster_name=${cluster_name:-tom-cluster}
machine=${machine:-e2-standard-4}
nodes=${nodes:-1}

image_name=${image_name:-tom-"$(echo ${tom_name} | tr '[A-Z]' '[a-z'])"-image}

# Region/location and container registry
if [[ "$platform" == "EKS" ]]; then
    image_repo="${image_repo:-tom-repo}/${image_name}"
    account_id="$(aws sts get-caller-identity --query Account --output text)"
    registry_host="${account_id}.dkr.ecr.${region}.amazonaws.com"
    image_full_name=${image_full_name:-"${registry_host}/${image_repo}"}
elif [[ "$platform" == "GKE" ]]; then
    location=${location:-us-central1}
    image_repo="${image_repo:-tom-repo}"
    registry_host=${registry_host:-"${location}-docker.pkg.dev"}
    image_full_name=${image_full_name:-"${registry_host}/${project_id}/${image_repo}/${image_name}"}
else
    echo invalid platform "$platform"
    exit 1
fi

# Kubernetes namespace and networking
kubernetes_namespace=${kubernetes_namespace:-tom}
tom_static_ip_name=${tom_static_ip_name:-tom-static-ip}

# Let's Encrypt Environment
letsencrypt_env=${letsencrypt_env:-staging}

postgres_image_tag=17.6.0

#--------------------------------------------------------------------------------
# service account names and ids
#--------------------------------------------------------------------------------

function service_account_email() {
    service_account_id="$1"
    { set +x; } 2>/dev/null
    echo "${service_account_id}@${project_id}.iam.gserviceaccount.com"
    set -x
}

# GDP service account for creating kubernetes nodes
node_service_account_id=knodes
node_service_account="$(service_account_email "$node_service_account_id")"

# kubernetes service account for django to manage data products in a
# Google Storage bucket
data_product_service_account_id=tomdataprod
data_product_service_account="$(service_account_email "$data_product_service_account_id")"
