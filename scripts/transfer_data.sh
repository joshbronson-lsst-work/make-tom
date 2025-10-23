# Save the directory containing this script to the $proj_dir variable.
pushd "$(dirname "${BASH_SOURCE[0]}")"; proj_dir=`pwd`; popd

set -euxo pipefail

tom_dir="$(dirname "$(dirname $proj_dir)")"

#--------------------------------------------------------------------------------
# configuration
#--------------------------------------------------------------------------------

# Load some configuration that is common to both scripts. 
. "${proj_dir}/common_config.sh"

backend_name=tom-"$(echo ${tom_name} | tr '[A-Z]' '[a-z]')"

#--------------------------------------------------------------------------------
# Migrate Data Products
#--------------------------------------------------------------------------------

if [[ "$platform" == "EKS" ]]; then
    backend=s3
else
    backend=gcs
fi

python "${proj_dir}/transfer_data_products.py" "$tom_name" "$bucket_name" "$backend"

#--------------------------------------------------------------------------------
# Define functions to interact with databases
#--------------------------------------------------------------------------------

function tom_dump() {
    python "manage.py" dumpdata "$@" --natural-primary --natural-foreign --indent 2
}

function tom_load() {
    kubectl -n "$kubernetes_namespace" exec -i deploy/"${backend_name}" -- \
            python /app/manage.py loaddata --format json - 
}

#--------------------------------------------------------------------------------
# Migrate SQL data
#--------------------------------------------------------------------------------

pushd "$tom_dir"

set +x >/dev/null
echo "================================================================================"
echo " THIS SCRIPT WILL DELETE YOUR DATA ON YOUR REMOTE TOM IF YOU SAY YES BELOW      "
echo "================================================================================"
set -x >/dev/null

read -r -p "Type YES to continue: " ans
if [[ "$ans" == "YES" ]]; then
    echo "OK. DELETING ALL DATA ON YOUR REMOTE TOM!"
    sleep 5
else
    echo "Aborting"
    exit 1
fi

kubectl -n "$kubernetes_namespace" exec -it deploy/"${backend_name}" -- \
        python /app/manage.py flush --no-input

kubectl -n "$kubernetes_namespace" exec -it deploy/"$backend_name" -- python /app/manage.py shell -c "from tom_common.models import Profile; Profile.objects.all().delete()"

# First, create users and authorizations. These models are often used
# by other models, and trying to load everything all at once when
# loading to a completely new database can result in foreign key
# errors:
#
#   - contenttypes      :: model registry mapping app labels to model names
#   - auth              :: authorizations used to interact with models
#   - auth              :: named set of permissions
#   - auth              :: users, including login information, etc.
#   - guardian          :: object-level permissions for individual records
#   - guardian          :: groups of object-level permissions

tom_dump contenttypes auth.permission   \
         auth.group                     \
         auth.user                      \
         guardian.userobjectpermission  \
         guardian.groupobjectpermission | tom_load


# Now dump the objects that are dependent on these.If this doesn't
# load, consider adding `admin.logentry` to the list of exclusions
# below.
#
#   - admin.logentry            :: records changes made by administrators. can be breaky.
#   - sessions                  :: login sessions not needed. re-login.
#   - authtoken                 :: auth tokens not needed. re-auth.
#   - contenttypes              :: already loaded
#   - auth                      :: already loaded
#   - tom_common.usersession    :: related to user sessions. not needed.
#   - guardian                  :: relevant objects already loaded

tom_dump                                \
  --exclude sessions                    \
  --exclude authtoken                   \
  --exclude contenttypes                \
  --exclude auth                        \
  --exclude tom_common.usersession      \
  --exclude tom_common.profile          \
  --exclude guardian | tom_load         \    

popd
