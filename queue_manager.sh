#!/bin/bash

QUEUE_DIR="/home/queue_jobs"
PENDING_DIR="$QUEUE_DIR/pending"
RUNTIME_DIR="$QUEUE_DIR/runtime"
DONE_DIR="$QUEUE_DIR/done"
FAILED_DIR="$QUEUE_DIR/failed"
LOCK_FILE="$RUNTIME_DIR/.manager.lock"

mkdir -p "$PENDING_DIR" "$RUNTIME_DIR" "$DONE_DIR" "$FAILED_DIR"

# Prevenir múltiples managers
if [ -f "$LOCK_FILE" ]; then
    echo "queue_manager ya está corriendo."
    exit 1
fi

touch "$LOCK_FILE"

echo "Iniciando queue_manager..."

while true; do
    if [ ! -s "$RUNTIME_DIR/queue_state.txt" ]; then
        sleep 5
        continue
    fi

    # Leer el primer trabajo en cola
    CURRENT_JOB=$(head -n 1 "$RUNTIME_DIR/queue_state.txt")

    # ¿Ya tiene "token" el job? Si no, crearlo
    if [ ! -f "$RUNTIME_DIR/${CURRENT_JOB}.ready" ]; then
        touch "$RUNTIME_DIR/${CURRENT_JOB}.ready"
        echo "Trabajo listo para ejecutar: $CURRENT_JOB"
    fi

    # Esperar a que el user_runner indique que terminó
    while [ -f "$RUNTIME_DIR/${CURRENT_JOB}.ready" ]; do
        sleep 5
    done

    # Sacarlo de la cola
    tail -n +2 "$RUNTIME_DIR/queue_state.txt" > "$RUNTIME_DIR/queue_state_tmp.txt"
    mv "$RUNTIME_DIR/queue_state_tmp.txt" "$RUNTIME_DIR/queue_state.txt"

    echo "Trabajo $CURRENT_JOB finalizado y removido de la cola."

    sleep 2
done

# Limpieza
rm -f "$LOCK_FILE"
