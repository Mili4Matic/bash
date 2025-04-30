#!/bin/bash

QUEUE_DIR="/home/queue_jobs"
RUNTIME_DIR="$QUEUE_DIR/runtime"
LOCK_FILE="$RUNTIME_DIR/.manager.lock"
QUEUE_FILE="$RUNTIME_DIR/queue_state.txt"
GPU_STATUS="$RUNTIME_DIR/gpu_status.json"

mkdir -p "$RUNTIME_DIR"

# Crear archivo de estado de GPUs si no existe
if [ ! -f "$GPU_STATUS" ]; then
  echo '{ "0": null, "1": null }' > "$GPU_STATUS"
fi

# Cancelar trabajo actual si hay .ready y lock existente (previo cierre inesperado)
if [ -f "$LOCK_FILE" ]; then
  echo "Detectado cierre anterior inesperado. Recuperando estado..."
  CURRENT_JOB=$(head -n 1 "$QUEUE_FILE" | cut -d: -f1)
  if [ -n "$CURRENT_JOB" ] && [ -f "$RUNTIME_DIR/${CURRENT_JOB}.ready" ]; then
    echo "Cancelando trabajo previo: $CURRENT_JOB"
    rm -f "$RUNTIME_DIR/${CURRENT_JOB}.ready"
    python3 -c "
import json
f = '$GPU_STATUS'
with open(f) as j:
    status = json.load(j)
for k, v in status.items():
    if v == '$CURRENT_JOB':
        status[k] = None
with open(f, 'w') as j:
    json.dump(status, j)
"
    mkdir -p "$QUEUE_DIR/failed"
    mv "$QUEUE_DIR/pending"/*/"$CURRENT_JOB" "$QUEUE_DIR/failed/" 2>/dev/null
  fi
  rm -f "$LOCK_FILE"
fi

# Limpieza al salir
cleanup() {
  echo "Saliendo de queue_manager, limpiando lock..."
  rm -f "$LOCK_FILE"
  exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# Crear nuevo lock
if [ -f "$LOCK_FILE" ]; then
  echo "queue_manager ya está corriendo."
  exit 1
fi

touch "$LOCK_FILE"
echo "Iniciando queue_manager con soporte GPU..."

while true; do
  if [ ! -s "$QUEUE_FILE" ]; then
    sleep 5
    continue
  fi

  LINE=$(head -n 1 "$QUEUE_FILE")
  JOB_ID=$(echo "$LINE" | cut -d: -f1)
  REQUESTED_GPUS=$(echo "$LINE" | cut -d: -f2)

  # Verificar si el trabajo ya tiene .ready y GPUs asignadas
  if [ -f "$RUNTIME_DIR/${JOB_ID}.ready" ]; then
    echo "Trabajo $JOB_ID ya tiene .ready, esperando a que termine..."
    while [ -f "$RUNTIME_DIR/${JOB_ID}.ready" ]; do
      sleep 5
    done
    tail -n +2 "$QUEUE_FILE" > "$QUEUE_FILE.tmp" && mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
    echo "Trabajo $JOB_ID finalizado. Avanzando."
    continue
  fi

  # Leer estado actual de GPUs
  GPU_IDS=$(python3 -c "
import json
f = '$GPU_STATUS'
with open(f) as j:
    status = json.load(j)
free = [k for k,v in status.items() if v is None]
req = $REQUESTED_GPUS
if len(free) >= req:
    print(','.join(free[:req]))
")

  if [ -n "$GPU_IDS" ]; then
    echo "Trabajo $JOB_ID liberado con GPUs: $GPU_IDS"
    echo "$GPU_IDS" > "$RUNTIME_DIR/${JOB_ID}.ready"

    # Reservar GPUs
    python3 -c "
import json
f = '$GPU_STATUS'
with open(f) as j:
    status = json.load(j)
for gpu in '$GPU_IDS'.split(','):
    status[gpu] = '$JOB_ID'
with open(f, 'w') as j:
    json.dump(status, j)
"

    # Esperar a que termine
    while [ -f "$RUNTIME_DIR/${JOB_ID}.ready" ]; do
      sleep 5
    done

    tail -n +2 "$QUEUE_FILE" > "$QUEUE_FILE.tmp" && mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
    echo "Trabajo $JOB_ID completado. Avanzando."
  else
    # Esperar a que se liberen GPUs suficientes
    sleep 5
  fi
done
