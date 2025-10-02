FROM python:3.12-slim

ARG TOM_NAME

COPY ${TOM_NAME}/requirements.txt /initial_requirements.txt

RUN pip install --root-user-action=ignore --no-cache-dir -r /initial_requirements.txt

# Share layers above this to the greatest extent possible.
COPY ${TOM_NAME} /app

RUN python /app/manage.py collectstatic --noinput

workdir /app
