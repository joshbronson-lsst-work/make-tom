from django.core.files import File

import argparse
import django
import os
import sys


def load_observations(fits_files):
    from tom_dataproducts.models import DataProduct
    from tom_targets.models import Target
    
    for t in Target.objects.all().iterator():
        print(t)
        break
    
    else:
        print('no targets found!')
        sys.exit(1)
    
    for fname in fits_files:
        with open(fname, 'rb') as obs_file:
            obs_name = os.path.basename(fname)
            print(f'loading observation {obs_name} from {fname}')
    
            dp = DataProduct.objects.create(
                target=t,
                product_id=obs_name,
                data=File(obs_file, name=obs_name),
                data_product_type='fits_file',
            )
    
            print(dp.data.url)
    

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument("tom_name", help='path to local TOM created in this project')
    p.add_argument("fits_files", nargs="+", help='FITS files to load into TOM')
    args = p.parse_args()

    os.environ.setdefault("DJANGO_SETTINGS_MODULE", f"{args.tom_name}.settings")
    
    fits_files = [
        os.path.abspath(f) for f in args.fits_files
    ]
    # assume that we are liviing within a TOM
    tom_dir = os.path.abspath(
        os.path.dirname(
            os.path.dirname(
                os.path.dirname(
                    os.path.abspath(__file__)
                )
            ),
        ),
    )
    if tom_dir not in sys.path:
        sys.path.insert(0, tom_dir)

    old_dir = os.path.abspath(os.curdir)
    os.chdir(tom_dir)
    try:
        django.setup()
        load_observations(fits_files)
    finally:
        os.chdir(old_dir)
