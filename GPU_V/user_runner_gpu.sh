#!/bin/bash

if [[ "$1" == "--gpus" ]]; then
    REQUESTED_GPUS=$2
    shift 2
else
    REQUESTED_GPUS=1
fi

if [ $# -lt 1 ]; then
    echo "Uso: $0 [--gpus 1|2] /ruta/al/archivo.py"
    exit 1
fi

ORIGINAL_JOB_FILE=$(realpath "$1")
USERNAME=$(whoami)
QUEUE_DIR="/home/queue_jobs"
PENDING_DIR="$QUEUE_DIR/pending/$USERNAME"
RUNTIME_DIR="$QUEUE_DIR/runtime"
LOGS_DIR="$QUEUE_DIR/logs"
mkdir -p "$PENDING_DIR" "$RUNTIME_DIR" "$LOGS_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RAND=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 5)
JOB_ID="${USERNAME}_${TIMESTAMP}_${RAND}"

DEST_DIR="$PENDING_DIR/$JOB_ID"
mkdir -p "$DEST_DIR"
ln -s "$ORIGINAL_JOB_FILE" "$DEST_DIR/$(basename "$ORIGINAL_JOB_FILE")"

echo "$JOB_ID:$REQUESTED_GPUS" >> "$RUNTIME_DIR/queue_state.txt"
echo "Trabajo a\u00f1adido con ID: $JOB_ID (GPUs solicitadas: $REQUESTED_GPUS)"

# ---- Esperar turno ----
echo "Esperando turno para el trabajo $JOB_ID..."

spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
spin_index=0

while true; do
    POSITION=$(grep -n "^$JOB_ID" "$RUNTIME_DIR/queue_state.txt" | cut -d: -f1)

    if [ -z "$POSITION" ]; then
        echo "El trabajo $JOB_ID ha desaparecido de la cola."
        exit 1
    fi

    if [ -f "$RUNTIME_DIR/${JOB_ID}.ready" ]; then
        echo -e "\n\u00a1Es tu turno! Ejecutando..."
        break
    else
        printf "\r${spin[$spin_index]} Tu posici\u00f3n en la cola es: $POSITION"
        spin_index=$(( (spin_index + 1) % 10 ))
    fi

    sleep 0.5
done

GPU_IDS=$(cat "$RUNTIME_DIR/${JOB_ID}.ready")

# ---- Ejecutar trabajo ----
JOB_SYMLINK=$(find "$QUEUE_DIR/pending/$USERNAME/$JOB_ID/" -type l -name "*.py" | head -n 1)
REAL_JOB_FILE=$(readlink -f "$JOB_SYMLINK")
REAL_DIR=$(dirname "$REAL_JOB_FILE")

ENV_NAME=$(grep -i "^# *conda_env" "$REAL_JOB_FILE" | sed -E 's/^# *conda_env:?[ ]*//;s/[[:space:]]*$//')
if [ -z "$ENV_NAME" ]; then
    echo "ERROR: No se especifico entorno conda."
    exit 1
fi

source ~/anaconda3/etc/profile.d/conda.sh
conda activate "$ENV_NAME"

cd "$REAL_DIR"

export CUDA_VISIBLE_DEVICES=$GPU_IDS
stdbuf -oL python -u "$(basename "$REAL_JOB_FILE")" | tee "$LOGS_DIR/${JOB_ID}.log"
EXIT_CODE=${PIPESTATUS[0]}

conda deactivate

rm -f "$RUNTIME_DIR/${JOB_ID}.ready"

# Liberar GPUs del status.json
python3 << EOF
import json
import os
f = "/home/queue_jobs/runtime/gpu_status.json"
with open(f, 'r') as j:
    status = json.load(j)
for gpu in "$GPU_IDS".split(','):
    status[gpu.strip()] = None
with open(f, 'w') as j:
    json.dump(status, j)
EOF

if [ \$EXIT_CODE -eq 0 ]; then
    mkdir -p "$QUEUE_DIR/done/$USERNAME"
    mv "$QUEUE_DIR/pending/$USERNAME/$JOB_ID" "$QUEUE_DIR/done/$USERNAME/"
    echo -e "\e[Trabajo ejecutado correctamente.\e[0m"
else
    mkdir -p "$QUEUE_DIR/failed/$USERNAME"
    mv "$QUEUE_DIR/pending/$USERNAME/$JOB_ID" "$QUEUE_DIR/failed/$USERNAME/"
    echo -e "\e[Trabajo fallo durante la ejecucion.\e[0m"
fi
