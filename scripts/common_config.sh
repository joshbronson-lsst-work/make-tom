#!/usr/bin/env sh

#--------------------------------------------------------------------------------
# Configuration with environment overrides.
# Export any of these variables before running the launcher to override defaults.
#
# REQUIRED (set here or in your shell):
#   - tom_name            Short identifier for this TOM deployment
#   - tom_hostname        Public URL (DNS hostname) you will use
#   - certmanager_email   Email used by Let's Encrypt (cert-manager)
#
# Notes:
# - "Hostname" here means the website URL, not an astronomical "Target".
# - Tools needed locally: gcloud, kubectl, helm, docker.
# - `gcloud auth login` opens a browser tab; follow the prompts.
#--------------------------------------------------------------------------------

# TOM name (REQUIRED)
tom_name=${tom_name:-}
if [ -z "$tom_name" ]; then
  echo "ERROR: tom_name is required. Set it in the environment or scripts/common_config.sh" >&2
  exit 1
fi


# GCP and cluster configuration
project_id="$(echo ${project_id:-tom-${tom_name}-project} | tr '[A-Z]' '[a-z]')"
zone=${zone:-"us-central1-a"}

proj_descr=${proj_descr:-"TOM Project"}
cluster_name=${cluster_name:-tom-cluster}
machine=${machine:-e2-standard-4}
nodes=${nodes:-1}

# Region/location and container registry
location=${location:-us-central1}
registry_host=${registry_host:-"${location}-docker.pkg.dev"}

# Image coordinates
image_name=${image_name:-tom-"$(echo ${tom_name} | tr '[A-Z]' '[a-z'])"-image}
image_repo=${image_repo:-tom-repo}
image_full_name=${image_full_name:-"${registry_host}/${project_id}/${image_repo}/${image_name}"}
image_tag=${image_tag:-"dev"}
image=${image:-"${image_full_name}:${image_tag}"}

# Kubernetes namespace and networking
kubernetes_namespace=${kubernetes_namespace:-tom}
tom_static_ip_name=${tom_static_ip_name:-tom-static-ip}

# Let's Encrypt Environment
letsencrypt_env=${letsencrypt_env:-staging}

postgres_image_tag=17.6.0
