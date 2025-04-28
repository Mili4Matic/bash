#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Uso: $0 /ruta/al/archivo.py"
    exit 1
fi

JOB_FILE=$(realpath "$1")
USERNAME=$(whoami)
QUEUE_DIR="/home/queue_jobs/pending/$USERNAME"
RUNTIME_DIR="/home/queue_jobs/runtime"
mkdir -p "$QUEUE_DIR"
mkdir -p "$RUNTIME_DIR"

# ID único basado en timestamp + random
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RAND=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 5)
JOB_ID="${USERNAME}_${TIMESTAMP}_${RAND}"

DEST_DIR="$QUEUE_DIR/$JOB_ID"
mkdir -p "$DEST_DIR"

# Crear symlink al script
ln -s "$JOB_FILE" "$DEST_DIR/$(basename "$JOB_FILE")"

# Registrar en la cola
echo "$JOB_ID" >> "$RUNTIME_DIR/queue_state.txt"

echo "Trabajo añadido con ID: $JOB_ID"
