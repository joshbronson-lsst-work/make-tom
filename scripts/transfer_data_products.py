from django.core.files import File
from django.core.files.storage import default_storage
from django.core.files.base import ContentFile
from functools import cached_property

from abc import ABC, abstractmethod
import argparse
import django
import os
import sys


class BaseTransfer(ABC):
    def __init__(self, bucket_name: str):
        self.bucket_name = bucket_name

    @cached_property
    @abstractmethod
    def storage(self):
        raise NotImplementedError

    def transfer(self):
        from tom_dataproducts.models import DataProduct
        for prod in DataProduct.objects.all().iterator():
            name = getattr(prod.data, 'name', None)
            if not name:
                print('skipping unnamed data product')
                continue
            if self.storage.exists(name):
                print(f'{name} exists on {self.storage}')
                continue

            with default_storage.open(name, 'rb') as f:
                print(f"copying {name} to {self.storage}")
                self.storage.save(name, ContentFile(f.read()))


class GoogleStorageTransfer(BaseTransfer):
    @cached_property
    def storage(self):
        # Requires django-storages[gcloud] and appropriate GCP credentials.
        from storages.backends.gcloud import GoogleCloudStorage
        return GoogleCloudStorage(bucket_name=self.bucket_name)


class S3StorageTransfer(BaseTransfer):
    @cached_property
    def storage(self):
        # Requires django-storages[s3] and AWS creds (IRSA, env, or shared config).
        from storages.backends.s3boto3 import S3Boto3Storage
        return S3Boto3Storage(bucket_name=self.bucket_name)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description='Copy local DataProducts to a cloud bucket (GCS or S3).')
    p.add_argument("tom_name", help='Destination bucket name (GCS or S3)')
    p.add_argument("bucket_name", help='Destination bucket name (GCS or S3)')
    p.add_argument("backend", choices=["gcs", "s3"], help='Cloud storage backend to use')
    args = p.parse_args()

    os.environ.setdefault("DJANGO_SETTINGS_MODULE", f"{args.tom_name}.settings")

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

        if args.backend == 's3':
            transfer = S3StorageTransfer(
                bucket_name=args.bucket_name
            )
        else:
            transfer = GoogleStorageTransfer(
                bucket_name=args.bucket_name,
            )

        transfer.transfer()
    finally:
        os.chdir(old_dir)
