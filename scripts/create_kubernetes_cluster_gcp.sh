# Save the directory containing this script to the $proj_dir variable.
pushd "$(dirname "${BASH_SOURCE[0]}")"; proj_dir=`pwd`; popd

set -euxo pipefail

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| configuration"
echo "|--------------------------------------------------------------------------------"
set -x

{ set +x; } 2>/dev/null
echo "| Load some configuration that is common to both scripts. "
set -x
. "${proj_dir}/common_config.sh"

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| There are two new concepts here: the gcloud commandline tool, and"
echo "| google compute engine projects."
echo "|"
echo "| You should already have installed and run the gcloud tool in the"
echo "| Google Compute Platform instructions. This is the first time we've"
echo "| created something with it. Many gcloud commands allow you to"
echo "| interact with objects in Google Compute Platform. You can generally"
echo "| \"list,\" \"describe,\" and \"delete\" objects, among other things."
echo "|"
echo "| Here we are idempotently creating a Google Compute Platform"
echo "| project. A project is a container for many of the objects that will"
echo "| be created below. If you delete a project, it will tidily delete the"
echo "| objects within it. Projects can be used to separate different objets"
echo "| to keep things neat."
echo "| --------------------------------------------------------------------------------"
set -x

{ set +x; } 2>/dev/null
echo "| First, check to see that the project exists. Standard input and"
echo "| standard error are both redirected to /dev/null here, meaning that"
echo "| they will not be displayed. This is to avoid the confusion of error"
echo "| messages being displayed when the project doesn't exist. It is"
echo "| expected that the project does not exist initially."
echo "|"
echo "| Checking in this way will avoid recreating a project that already"
echo "| exists, which would otherwise result in failure, thus allowing the"
echo "| script to be rerun even after a project is successfully created."
set -x
if gcloud projects describe "$project_id" >/dev/null 2>/dev/null; then 
    # If a project already exists, there is no need to do anything.
    { set +x; } 2>/dev/null
    echo OK. project exists: "$project_id". continuing.
    set -x
else
    # If a project does not exist, create it! A project requires an ID
    # and a name. The name is free-form.
    { set +x; } 2>/dev/null
    echo creating "$project_id"
    set -x
    gcloud projects create "$project_id" --name="$proj_descr"
fi

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| The gcloud config command configures the gcloud command itself. It"
echo "| sets the project to the potentially newly created project so that"
echo "| commands below will run by default in this project."
echo "|--------------------------------------------------------------------------------"
echo
set -x
gcloud config set project "$project_id"

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Now retrieve the billing account. The script expects exactly one"
echo "| billing account to be created. This should be true if you've"
echo "| followed the instructions for setting up the Google Compute"
echo "| Platform. But if you haven't, you may not have a billing account. If"
echo "| you've set up more than one billing account, this will also fail."
echo "| "
echo "| Billing accounts can be listed, as you can see below, with the"
echo "| \`gcloud billing accounts\` command. You can list your billing"
echo "| accounts with the command"
echo "|"
echo "|     gcloud billing accounts list"
echo "|"
echo "| The ACCOUNT_ID column is the one we're interested in. Given project"
echo "| id \$project_id and billing account \$billing_account, you can"
echo "| manually link ACCOUNT_ID, you should be able to link them with this"
echo "| command, which you'll see below:"
echo "|"
echo "|     gcloud billing projects link \"\$project_id\" --billing-account=\"\$billing_account\""
echo "|"
echo "| After that, the test below should succeed and the script should be"
echo "| skipped on successive runs."
echo "| --------------------------------------------------------------------------------"
set -x

{ set +x; } 2>/dev/null
echo "| First, get the billing account associated with $project_id"
set -x
billing_account="$(gcloud billing projects describe "$project_id" --format="value(billingAccountName)")"

{ set +x; } 2>/dev/null
echo "| Check to ensure that it exists, that is, that it is not empty."
set -x
if [[ -z "$billing_account" ]]; then
    { set +x; } 2>/dev/null
    echo "|OK. project does not have a billing account. linking one..."
    set -x

    # Get all of the billing accounts and count how many there are.
    billing_accounts="$(gcloud billing accounts list --format="value(ACCOUNT_ID)")"
    num_accounts="$(echo "$billing_accounts" | wc -w | awk '{$1=$1};1')"

    if [[ $num_accounts == 0 ]]; then
        { set +x; } 2>/dev/null
        echo A billing account must be set up first on Google Compute Engine.
        set -x
        exit 1
    elif [[ $num_accounts == 1 ]]; then
        billing_account="$billing_accounts"
        { set +x; } 2>/dev/null
        echo linking "$project_id" with billing account "$billing_account"
        set -x
        gcloud billing projects link "$project_id" --billing-account="$billing_account"
    else
        { set +x; } 2>/dev/null
        echo Too many billing accounts. Choose manually and rerun this script.
        set -x
        gcloud billing accounts list --format="value(ACCOUNT_ID)"
        exit 1
    fi
fi

{ set +x; } 2>/dev/null
echo "| Not all services are enabled on a newly created Google Compute"
echo "| Platform instance. You'll need to create these in order to push"
echo "| containers to Google Compute Platforma and spin up Kubernetes"
echo "| objects."
set -x
gcloud services enable \
       container.googleapis.com \
       compute.googleapis.com \
       iam.googleapis.com \
       containerregistry.googleapis.com \
       iamcredentials.googleapis.com


{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Create and configure a new service account specifically for"
echo "| Kubernetes. A service account, unlike your Google Compute Platform"
echo "| user account, is designed to be run by long-running automated"
echo "| processes (services)."
echo "|"
echo "| The kubernetes service account has access to artifact storage as"
echo "| well as diagnostic and telemetry information about processes running"
echo "| within Google Compute Engine. It is used, for example, to pull"
echo "| docker images onto Kubernetes "pods," which are containers running"
echo "| in your Kubenetes environments."
echo "| --------------------------------------------------------------------------------"
set -x

echo "| Utility functions to create and wait for service accounts and assign roles"

function assign_roles() {
    service_account_id="$1"; shift
    service_account="$(service_account_email "$service_account_id")"
    
    for role in "$@"; do
	echo ensuring role "$service_account has role $role"
	gcloud projects add-iam-policy-binding "$project_id" \
               --member="serviceAccount:${service_account}"  \
	       --role="roles/${role}"
    done
}

function create_service_account() {

    # First, create the service account itself idempotently: check if it
    # exists, and create it if not.
    service_account_id="$1"; shift

    service_account="$(service_account_email "$service_account_id")"
    if ! gcloud iam service-accounts describe "${service_account}" >/dev/null 2>/dev/null ; then
    { set +x; } 2>/dev/null
    echo "|Creating kubernetes node service account $service_account_id"
    set -x
	gcloud iam service-accounts create "$service_account_id"
	sleep 10
    fi

    # Wait for the service account to exist. Sometimes they take a few
    # minutes to create.
    { set +x; } 2>/dev/null
    echo "|Waiting for creation of ${service_account}"
    set -x
    for try in {1..5}; do
	# Check for the service account 
	if gcloud iam service-accounts describe "${service_account}" ; then
            { set +x; } 2>/dev/null
            echo Service account "${service_account} created."
            set -x
            break
	else
            { set +x; } 2>/dev/null
            echo "|Problem. retrying in 60 seconds. This should not fail more than twice."
            set -x
            sleep 60
	fi
    done
    
    assign_roles "$service_account_id" "$@"
}

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Create a service account to manage Kubernetes nodes."
echo "|--------------------------------------------------------------------------------"
set -x

{ set +x; } 2>/dev/null
echo "| Ensure that the service account has roles sufficient for spinning up"
echo "| Kubernetes nodes, which includes the need to read from an artifact"
echo "| registry and pull docker images from it."
set -x

create_service_account "$node_service_account_id" \
		       artifactregistry.reader \
		       logging.logWriter \
		       monitoring.metricWriter

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Create a service account to manage TOM data products."
echo "|--------------------------------------------------------------------------------"
set -x

{ set +x; } 2>/dev/null
echo "| Ensure that the role has the ability to manage Google Storage"
echo "| buckets. The iam.serviceAccountTokenCreator role is also necessary"
echo "| to generate "signed blobs," which are incorporated into URLs used to"
echo "| access private Google Storage buckets. This allows TOM and Django to"
echo "| generate URLs that allow their user to access data products in these"
echo "| buckets without opening the buckets to the outside world."
set -x

create_service_account "$data_product_service_account_id" \
		       storage.objectAdmin \
		       iam.serviceAccountTokenCreator


{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Create and configure bucket to store data prdoucts on"
echo "| --------------------------------------------------------------------------------"
set -x

{ set +x; } 2>/dev/null
echo "| Create the bucket, if it doesn't exist."
set -x
if gsutil ls "gs://${bucket_name}" > /dev/null 2>/dev/null; then
    { set +x; } 2>/dev/null
    echo "|OK. ${bucket_name} already exists. continuing."
    set -x
else
    { set +x; } 2>/dev/null
    echo "|Creating ${bucket_name}"
    set -x
    gsutil mb -p "$project_id" -l "$region" -b on "gs://${bucket_name}"
fi

sleep 5

{ set +x; } 2>/dev/null
echo "| Grant the service account access to the bucket we'll use for data"
echo "| products."
set -x
gcloud storage buckets add-iam-policy-binding "gs://${bucket_name}" \
  --member="serviceAccount:${data_product_service_account}" \
  --role=roles/storage.objectAdmin

{ set +x; } 2>/dev/null
echo "| Configure the bucket to allow requests from Javascript from within"
echo "| Django. This allows the JS9 viewer to work in Django."
set -x
cors_conf="$(mktemp)"
cat >"$cors_conf" <<EOF
[
  {
    "origin": [
      "https://${tom_hostname}",
      "http://localhost:8000",
      "http://127.0.0.1:8000"
    ],
    "method": ["GET", "HEAD", "OPTIONS"],
    "responseHeader": [
      "Content-Type",
      "Content-Length",
      "Accept-Ranges",
      "Content-Range",
      "ETag",
      "Last-Modified",
      "x-goog-hash"
    ],
    "maxAgeSeconds": 3600
  }
]
EOF

gcloud storage buckets update "gs://${bucket_name}" --cors-file="$cors_conf"

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Create a Kubernetes cluster with a configurable nubmer of nodes. A"
echo "| single node can run multiple Kubernetes pods. Many rules determine"
echo "| which pods are assinged to which nodes, including resource limits"
echo "| and explicit selectors."
echo "|--------------------------------------------------------------------------------"
echo
set -x
if ! gcloud container clusters describe --zone "$zone" "$cluster_name" >/dev/null 2>/dev/null; then
    { set +x; } 2>/dev/null
    echo "|OK. cluster ${cluster_name} does not exist. creating it."
    set -x
    gcloud container clusters create "$cluster_name"    \
           --zone "$zone"                               \
           --num-nodes="$nodes"                         \
           --service-account="${node_service_account}"  \
           --machine-type="$machine"                    \
           --workload-metadata=GKE_METADATA             \
           --workload-pool="${project_id}.svc.id.goog"  \
           --enable-ip-alias
fi

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Now, as a final step, we need to allow a to-be-created Kubernetes"
echo "| service account to impersonate the data product service account we"
echo "| created above. This is because the service account used by the"
echo "| Django pod responsible for serving up access to the Google Storage"
echo "| bucket will actually have a Kubernetes key, not a Google Storage"
echo "| key."
echo "|--------------------------------------------------------------------------------"
echo
set -x
gcloud iam service-accounts add-iam-policy-binding "${data_product_service_account_id}@${project_id}.iam.gserviceaccount.com" \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${project_id}.svc.id.goog[${kubernetes_namespace}/${data_product_service_account_id}]"


{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Finally, we will install the gke-gcloud-auth-plugin, and then use"
echo "| its get-credentials command to configure the kubernetes kubectl"
echo "| command to use the newly created kubernetes cluster."
echo "|--------------------------------------------------------------------------------"
echo
set -x
gcloud components install gke-gcloud-auth-plugin
gcloud container clusters get-credentials "$cluster_name" --zone "$zone" --project "$project_id"
