from django.core.files import File
from django.core.files.storage import default_storage
from django.core.files.base import ContentFile
from functools import cached_property
from storages.backends.gcloud import GoogleCloudStorage

import argparse
import django
import os
import sys


class GoogleStorageTransfer:
    def __init__(self, tom_name, gcs_bucket_name):
        self.tom_name = tom_name
        self.gcs_bucket_name = gcs_bucket_name

    @cached_property
    def storage(self):
        return GoogleCloudStorage(bucket_name=self.gcs_bucket_name)

    def transfer(self):
        from tom_dataproducts.models import DataProduct
        for prod in DataProduct.objects.all().iterator():
            name = prod.data.name
            if not name:
                print('skipping unnamed data product')
                continue
            if self.storage.exists(name):
                print(f'{name} exists on {self.storage}')
                continue
            
            with default_storage.open(name, 'rb') as f:
                print(f"copying {name} to {self.storage}")
                self.storage.save(name, ContentFile(f.read()))


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument("tom_name", help='path to local TOM created in this project')
    p.add_argument("gcs_bucket_name", help='Name of Gogole Storage Bucket to write to')
    args = p.parse_args()

    os.environ.setdefault("DJANGO_SETTINGS_MODULE", f"{args.tom_name}.settings")
    
    tom_dir = os.path.abspath(
        os.path.join(
            os.path.dirname(
                os.path.dirname(
                    os.path.abspath(__file__)
                )
            ),
            args.tom_name,
        )
    )
    if tom_dir not in sys.path:
        sys.path.insert(0, tom_dir)

    old_dir = os.path.abspath(os.curdir)
    os.chdir(tom_dir)
    try:
        django.setup()

        print('=' * 80)
        print("THIS SCRIPT WILL POINT ALL DATA PRODUCTS IN YOUR LOCAL TOM TO A NEW REPOSITORY")
        print('=' * 80)
        print('')
        sys.stdout.write('Continue? (y/N) ')
        sys.stdout.flush()
        
        if sys.stdin.readline().strip().lower() not in ['y', 'yes']:
            sys.exit(1)
    
        print('OK! Continuing. This will not delete the observations themselves.')
        print('To recover your data products, you will need to manually update')
        print('your database to point to the old storage.')

        GoogleStorageTransfer(
            tom_name=args.tom_name,
            gcs_bucket_name=args.gcs_bucket_name,
        ).transfer()
    finally:
        os.chdir(old_dir)
