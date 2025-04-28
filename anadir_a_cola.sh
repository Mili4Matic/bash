#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Uso: $0 /ruta/al/archivo.py"
    exit 1
fi

JOB_FILE=$(realpath "$1")
USERNAME=$(whoami)
QUEUE_DIR="/home/queue_jobs/pending/$USERNAME"

mkdir -p "$QUEUE_DIR"

# Nombre unico basado en timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BASENAME=$(basename "$JOB_FILE" .py)
DEST_DIR="$QUEUE_DIR/${BASENAME}_${TIMESTAMP}"

mkdir -p "$DEST_DIR"

# Crear el enlace simbolico al archivo real
ln -s "$JOB_FILE" "$DEST_DIR/$(basename "$JOB_FILE")"

echo "Trabajo añadido a la cola en $DEST_DIR (symlink a $JOB_FILE) [JOB SUCCESSFULL]"
