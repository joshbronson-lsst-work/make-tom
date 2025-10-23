pushd "$(dirname "${BASH_SOURCE[0]}")"; proj_dir=`pwd`; popd

set -euxo pipefail

. "${proj_dir}/common_config.sh"

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Ensuring S3 bucket for data products exists: ${bucket_name} (region: ${region})"
echo "|--------------------------------------------------------------------------------"
set -x

if aws s3api head-bucket --bucket "$bucket_name" &>/dev/null; then
  echo "| OK. S3 bucket ${bucket_name} exists."
else
  if [ "$region" = "us-east-1" ]; then
      extra_args=()
  else
      extra_args=(--create-bucket-configuration LocationConstraint="$region")
  fi
  aws s3api create-bucket --bucket "$bucket_name" --acl private "${extra_args[@]}" | cat
fi

aws s3api put-bucket-cors	\
    --bucket "$bucket_name"	\
    --cors-configuration	\
    file://<(
cat <<EOF
  {
    "CORSRules": [
      {
        "ID": "allow-cors-${tom_hostname}",
        "AllowedOrigins": ["https://${tom_hostname}"],
        "AllowedHeaders": ["*"],
        "AllowedMethods": ["GET", "HEAD"],
        "ExposeHeaders": ["Accept-Ranges", "Content-Range", "ETAG", "Content-Length"],
        "MaxAgeSeconds": 3000
      }
   ]
 }
EOF
)

{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Creating IAM policy for bucket access and binding via IRSA"
echo "|--------------------------------------------------------------------------------"
set -x

tom_s3_policy_name="tom-${tom_name_lowercase}-s3-access"
tom_s3_policy_doc=$(mktemp)
cat >"$tom_s3_policy_doc" <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::${bucket_name}"]
    },
    {
      "Sid": "ObjectRW",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": ["arn:aws:s3:::${bucket_name}/*"]
    }
  ]
}
POLICY

tom_s3_policy_arn="arn:aws:iam::${account_id}:policy/${tom_s3_policy_name}"
if ! aws iam get-policy --policy-arn "$tom_s3_policy_arn" >/dev/null 2>/dev/null; then
  aws iam create-policy --policy-name "$tom_s3_policy_name" \
    --policy-document "file://${tom_s3_policy_doc}" >/dev/null
fi


{ set +x; } 2>/dev/null
echo "|--------------------------------------------------------------------------------"
echo "| Creating IAM policy for Helm-installed load balancer controller"
echo "|--------------------------------------------------------------------------------"
set -x

load_balancer_policy_arn="arn:aws:iam::${account_id}:policy/AWSLoadBalancerControllerIAMPolicy"
if ! aws iam get-policy --policy-arn "arn:aws:iam::${account_id}:policy/AWSLoadBalancerControllerIAMPolicy" &>/dev/null; then
    policy_file=$(mktemp)
    curl -L -o "$policy_file" 'https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json'
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document "file://${policy_file}" >/dev/null
fi


cluster_config_file=$(mktemp)

cat >"$cluster_config_file" <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: "$cluster_name"
  region: "$region"

iam:
  serviceAccounts:
  - metadata:
      name: aws-load-balancer-controller
      namespace: kube-system
      labels: 
        app.kubernetes.io/name: aws-load-balancer-controller
    roleName: alb-controller-irsa
    attachPolicyARNs:
     - "$load_balancer_policy_arn"
  - metadata:
      name: "$data_product_service_account_id"
      namespace: "$kubernetes_namespace"
    attachPolicyARNs:
     - "$tom_s3_policy_arn"
  withOIDC: true

autoModeConfig:
  enabled: true


addons:
- name: aws-ebs-csi-driver
  attachPolicyARNs:
   - arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
EOF

if ! eksctl get cluster "$cluster_name" &>/dev/null; then

    { set +x; } 2>/dev/null
    echo "|--------------------------------------------------------------------------------"
    echo "| Creating Kubernetes cluster ${cluster_name}. This will take a few minutes."
    echo "|--------------------------------------------------------------------------------"
    set -x

    eksctl create cluster -f "$cluster_config_file"
else
    echo OK. cluster "$cluster_name" exists. upgrading.
    eksctl upgrade cluster -f "$cluster_config_file"
    eksctl create iamserviceaccount -f "$cluster_config_file" --approve
fi

kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: auto-ebs-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
allowedTopologies:
- matchLabelExpressions:
  - key: eks.amazonaws.com/compute-type
    values:
    - auto
provisioner: ebs.csi.eks.amazonaws.com
volumeBindingMode: WaitForFirstConsumer

parameters:
  type: gp3
EOF
