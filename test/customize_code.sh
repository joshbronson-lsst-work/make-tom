pushd "$(dirname "${BASH_SOURCE[0]}")"; proj_dir=`pwd`; popd

set -euxo pipefail

pushd "$proj_dir"/..

. scripts/common_config.sh

rsync -av ./test/custom_code/ ../custom_code

pushd ..

.  ./env/bin/activate

python ./manage.py makemigrations custom_code
python ./manage.py migrate
python ./manage.py shell -c "
from tom_targets.models import Target
from custom_code.models import TargetLabel as L
t = Target.objects.first() or Target.objects.create(name='DEVTEST')
L.objects.create(target=t, text='DEVTEST')
print('Created label', t.name)
"
