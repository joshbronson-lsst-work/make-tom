# Save the directory containing this script to the $proj_dir variable.
pushd "$(dirname "${BASH_SOURCE[0]}")"; proj_dir=`pwd`; popd


#--------------------------------------------------------------------------------
# This script is designed to be run over and over without causing harm
# to a system. Successive runs should push the system toward a good
# state and preserve that good state, whether or not the script
# fails. This design philosophy is common in devops, and scripts that
# adhere to it are called idempotent. 
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
# configuration
#--------------------------------------------------------------------------------

# Load some configuration that is common to both scripts. 
. "${proj_dir}/common_config.sh"

backend_name=tom-"$(echo ${tom_name} | tr '[A-Z]' '[a-z]')"

#--------------------------------------------------------------------------------
# Migrate Data Products
#--------------------------------------------------------------------------------

python "${proj_dir}/transfer_data_products.py" "$tom_name" "$bucket_name"

#--------------------------------------------------------------------------------
# Define functions to interact with databases
#--------------------------------------------------------------------------------

function tom_dump() {
    python "${tom_name}/manage.py" dumpdata "$@" --natural-primary --natural-foreign --indent 2 
}

function tom_load() {
    kubectl -n "$kubernetes_namespace" exec -i deploy/"${backend_name}" -- \
            python /app/manage.py loaddata --format json - 
}

#--------------------------------------------------------------------------------
# Migrate SQL data
#--------------------------------------------------------------------------------

set +x >/dev/null
echo "--------------------------------------------------------------------------------"
echo " THIS SCRIPT WILL DELETE YOUR DATA ON YOUR TARGET TOM IF YOU SAY YES BELOW      "
echo "--------------------------------------------------------------------------------"
set -x >/dev/null

kubectl -n "$kubernetes_namespace" exec -it deploy/"${backend_name}" -- \
        python /app/manage.py flush

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
  --exclude guardian | tom_load         \    
