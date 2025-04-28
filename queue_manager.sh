#!/bin/bash

QUEUE_DIR="/home/queue_jobs"
PENDING_DIR="$QUEUE_DIR/pending"
RUNTIME_DIR="$QUEUE_DIR/runtime"
DONE_DIR="$QUEUE_DIR/done"
FAILED_DIR="$QUEUE_DIR/failed"
LOCK_FILE="$RUNTIME_DIR/.manager.lock"

mkdir -p "$PENDING_DIR" "$RUNTIME_DIR" "$DONE_DIR" "$FAILED_DIR"

# Limpieza segura
cleanup() {
    echo "Saliendo de queue_manager, limpiando lock..."
    rm -f "$LOCK_FILE"
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

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

    CURRENT_JOB=$(head -n 1 "$RUNTIME_DIR/queue_state.txt" | tr -d '\r\n')

    # Solo si no hay ready, crearlo
    if [ ! -f "$RUNTIME_DIR/${CURRENT_JOB}.ready" ]; then
        echo "Trabajo ${CURRENT_JOB} liberado."
        touch "$RUNTIME_DIR/${CURRENT_JOB}.ready"
    fi

    # Esperar a que el user_runner termine
    while [ -f "$RUNTIME_DIR/${CURRENT_JOB}.ready" ]; do
        sleep 5
    done

    # Sacar el trabajo de la cola
    tail -n +2 "$RUNTIME_DIR/queue_state.txt" > "$RUNTIME_DIR/queue_state_tmp.txt"
    mv "$RUNTIME_DIR/queue_state_tmp.txt" "$RUNTIME_DIR/queue_state.txt"

    echo "Trabajo $CURRENT_JOB completado. Avanzando."

    sleep 2
done
