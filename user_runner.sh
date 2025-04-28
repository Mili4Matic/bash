#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Uso: $0 /ruta/al/archivo.py"
    exit 1
fi

ORIGINAL_JOB_FILE=$(realpath "$1")
USERNAME=$(whoami)
QUEUE_DIR="/home/queue_jobs"
PENDING_DIR="$QUEUE_DIR/pending/$USERNAME"
RUNTIME_DIR="$QUEUE_DIR/runtime"
LOGS_DIR="$QUEUE_DIR/logs"
mkdir -p "$PENDING_DIR" "$RUNTIME_DIR" "$LOGS_DIR"

# Añadir trabajo a la cola
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RAND=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 5)
JOB_ID="${USERNAME}_${TIMESTAMP}_${RAND}"

DEST_DIR="$PENDING_DIR/$JOB_ID"
mkdir -p "$DEST_DIR"
ln -s "$ORIGINAL_JOB_FILE" "$DEST_DIR/$(basename "$ORIGINAL_JOB_FILE")"

echo "$JOB_ID" >> "$RUNTIME_DIR/queue_state.txt"

echo "Trabajo añadido con ID: $JOB_ID"

# ---- Esperar turno ----
echo "Esperando turno para el trabajo $JOB_ID..."

spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
spin_index=0

while true; do
    POSITION=$(grep -n "^$JOB_ID$" "$RUNTIME_DIR/queue_state.txt" | cut -d: -f1)

    if [ -z "$POSITION" ]; then
        echo "El trabajo $JOB_ID ha desaparecido de la cola."
        exit 1
    fi

    if [ -f "$RUNTIME_DIR/${JOB_ID}.ready" ]; then
        echo -e "\n¡Es tu turno! Ejecutando..."
        break
    else
        printf "\r${spin[$spin_index]} Tu posición en la cola es: $POSITION"
        spin_index=$(( (spin_index + 1) % 10 ))
    fi

    sleep 0.5
done

# ---- Ejecutar trabajo ----
JOB_SYMLINK=$(find "$QUEUE_DIR/pending/$USERNAME/$JOB_ID/" -type l -name "*.py" | head -n 1)
REAL_JOB_FILE=$(readlink -f "$JOB_SYMLINK")
REAL_DIR=$(dirname "$REAL_JOB_FILE")

ENV_NAME=$(head -n 1 "$REAL_JOB_FILE" | sed -n 's/^# *conda_env: *//p')

if [ -z "$ENV_NAME" ]; then
    echo "ERROR: No se especificó entorno conda en el script."
    exit 1
fi

# Cargar entorno base
source ~/anaconda3/etc/profile.d/conda.sh

cd "$REAL_DIR"

if [[ "$ENV_NAME" == /* ]]; then
    # Es una ruta absoluta
    ENV_PYTHON="$ENV_NAME/bin/python"
    stdbuf -oL "$ENV_PYTHON" -u "$(basename "$REAL_JOB_FILE")" | tee "$LOGS_DIR/${JOB_ID}.log"
else
    # Es un nombre de entorno
    conda activate "$ENV_NAME"
    stdbuf -oL python -u "$(basename "$REAL_JOB_FILE")" | tee "$LOGS_DIR/${JOB_ID}.log"
    conda deactivate
fi

EXIT_CODE=${PIPESTATUS[0]}

rm -f "$RUNTIME_DIR/${JOB_ID}.ready"

if [ $EXIT_CODE -eq 0 ]; then
    mkdir -p "$QUEUE_DIR/done/$USERNAME"
    mv "$QUEUE_DIR/pending/$USERNAME/$JOB_ID" "$QUEUE_DIR/done/$USERNAME/"
    echo "Trabajo ejecutado correctamente."
else
    mkdir -p "$QUEUE_DIR/failed/$USERNAME"
    mv "$QUEUE_DIR/pending/$USERNAME/$JOB_ID" "$QUEUE_DIR/failed/$USERNAME/"
    echo "Trabajo falló durante la ejecución."
fi
