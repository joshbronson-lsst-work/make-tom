FROM python:3.12-slim

ARG TOM_NAME

COPY requirements.txt /initial_requirements.txt

RUN pip install --root-user-action=ignore --no-cache-dir -r /initial_requirements.txt

RUN mkdir /app

COPY ${TOM_NAME} /app/${TOM_NAME}
COPY manage.py /app/manage.py
COPY templates/ /app/templates/
COPY static/ /app/static/
COPY custom_code/ /app/custom_code/
COPY local_settings.py /app/local_settings.py

RUN python /app/manage.py collectstatic --noinput

workdir /app
