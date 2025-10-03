import json
import os
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent

# DEBUG is True by default to match behavior in settings.py
DEBUG = os.getenv(
    "DEBUG",
    os.getenv("TOM_DEMO_DEBUG", "True")
).lower() in ("1","true","yes","on")


if "SECRET_KEY" in os.environ: 
    SECRET_KEY = os.environ["SECRET_KEY"]


ALLOWED_HOSTS = ['*']


if "CSRF_TRUSTED_ORIGINS" in os.environ:
    CSRF_TRUSTED_ORIGINS = [
        u.strip() 
        for u in os.environ["CSRF_TRUSTED_ORIGINS"].split(",") 
        if u.strip()
    ]


if os.getenv("DB_HOST"):
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql", 
            "NAME": os.getenv("DB_NAME","postgres"), 
            "USER": os.getenv("DB_USER","postgres"), 
            "PASSWORD": os.getenv("DB_PASS",""), 
            "HOST": os.getenv("DB_HOST"), "PORT": os.getenv("DB_PORT","5432")
        }
    }


MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    'django_htmx.middleware.HtmxMiddleware',
    'tom_common.middleware.Raise403Middleware',
    'tom_common.middleware.ExternalServiceMiddleware',
    'tom_common.middleware.AuthStrategyMiddleware',
]


if os.getenv("USE_WHITENOISE","1") == "1":
    MIDDLEWARE.insert(0, "whitenoise.middleware.WhiteNoiseMiddleware")
    STATICFILES_STORAGE = "whitenoise.storage.CompressedManifestStaticFilesStorage"


GS_BUCKET_NAME = os.environ.get("GS_BUCKET_NAME")
if GS_BUCKET_NAME:
    DEFAULT_FILE_STORAGE = 'storages.backends.gcloud.GoogleCloudStorage'
    GS_IAM_SIGN_BLOB = True

GS_DEFAULT_ACL = None

STATIC_ROOT = BASE_DIR / "staticfiles"

MEDIA_URL = "/data/"
MEDIA_ROOT = BASE_DIR / "data"

def update_settings(settings):
    if 'storages' not in settings['INSTALLED_APPS']:
        settings['INSTALLED_APPS'].append('storages')

