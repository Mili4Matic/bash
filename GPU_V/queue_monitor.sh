#!/bin/bash

QUEUE_DIR="/home/queue_jobs"
RUNTIME_DIR="$QUEUE_DIR/runtime"
QUEUE_FILE="$RUNTIME_DIR/queue_state.txt"
GPU_STATUS_FILE="$RUNTIME_DIR/gpu_status.json"

# Mostrar cola actual
if [ -f "$QUEUE_FILE" ]; then
  echo "\n📋 COLA ACTUAL:"
  nl -w2 -s'. ' "$QUEUE_FILE" | while read -r line; do
    JOB_ID=$(echo "$line" | cut -d: -f2 | xargs | cut -d: -f1)
    GPUS=$(echo "$line" | cut -d: -f3 | xargs)
    echo "   ➤ $JOB_ID (GPUs solicitadas: $GPUS)"
  done
else
  echo "\n📋 COLA ACTUAL: vacía"
fi

# Mostrar estado de las GPUs
if [ -f "$GPU_STATUS_FILE" ]; then
  echo "\n🖥️ ESTADO DE LAS GPUS:"
  python3 -c "
import json
with open('$GPU_STATUS_FILE') as f:
    status = json.load(f)
for gpu, job in status.items():
    if job:
        print(f'   GPU {gpu}: ocupado por {job}')
    else:
        print(f'   GPU {gpu}: libre')
"
else
  echo "\nNo se encontró gpu_status.json"
fi

echo
