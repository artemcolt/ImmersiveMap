#!/bin/sh
set -eu

mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb --ignore-existing "local/$NIGHT_LIGHTS_BUCKET"
mc anonymous set download "local/$NIGHT_LIGHTS_BUCKET"

if [ -d "/seed/$NIGHT_LIGHTS_BUCKET" ]; then
  mc cp --recursive "/seed/$NIGHT_LIGHTS_BUCKET/" "local/$NIGHT_LIGHTS_BUCKET/"
fi

if [ -d "/bundled-night-lights" ]; then
  mc mirror --overwrite "/bundled-night-lights/" "local/$NIGHT_LIGHTS_BUCKET/v1/tiles/"
fi
