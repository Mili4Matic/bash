#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Uso: $0 /ruta/al/archivo.py"
    exit 1
fi

ORIGINAL_JOB_FILE=$(realpath "$1")
USERNAME=$(whoami)
QUEUE_DIR="/home/queue_jobs"
RUNTIME_DIR="$QUEUE_DIR/runtime"
LOGS_DIR="$QUEUE_DIR/logs"
mkdir -p "$LOGS_DIR"

# Encontrar el job_id
JOB_ID=$(basename $(dirname $(find "$QUEUE_DIR/pending/$USERNAME/" -lname "$ORIGINAL_JOB_FILE" -print -quit)))

if [ -z "$JOB_ID" ]; then
    echo "No se encontró el trabajo en la cola."
    exit 1
fi

echo "Esperando turno para el trabajo $JOB_ID..."

# Esperar a que el manager cree el token de ready
while true; do
    # Calcular posición
    POSITION=$(grep -n "$JOB_ID" "$RUNTIME_DIR/queue_state.txt" | cut -d: -f1)

    if [ -z "$POSITION" ]; then
        echo "El trabajo $JOB_ID ha desaparecido de la cola."
        exit 1
    fi

    if [ -f "$RUNTIME_DIR/${JOB_ID}.ready" ]; then
        echo "¡Es tu turno! Ejecutando..."
        break
    else
        echo "Tu posición en la cola es: $POSITION"
    fi

    sleep 5
done

# Resolver symlink
JOB_SYMLINK=$(find "$QUEUE_DIR/pending/$USERNAME/$JOB_ID/" -type l -name "*.py" | head -n 1)
REAL_JOB_FILE=$(readlink -f "$JOB_SYMLINK")
REAL_DIR=$(dirname "$REAL_JOB_FILE")

# Leer entorno
ENV_NAME=$(head -n 1 "$REAL_JOB_FILE" | sed -n 's/^# *conda_env: *//p')

if [ -z "$ENV_NAME" ]; then
    echo "ERROR: No se especificó entorno en el script."
    exit 1
fi

# Activar entorno
source ~/anaconda3/etc/profile.d/conda.sh
conda activate "$ENV_NAME"

# Ejecutar y loggear
cd "$REAL_DIR"
python "$(basename "$REAL_JOB_FILE")" | tee "$LOGS_DIR/${JOB_ID}.log"
EXIT_CODE=${PIPESTATUS[0]}

conda deactivate

# Borrar token de ready para que manager pase al siguiente
rm -f "$RUNTIME_DIR/${JOB_ID}.ready"

# Mover trabajo a done o failed
if [ $EXIT_CODE -eq 0 ]; then
    mkdir -p "$QUEUE_DIR/done/$USERNAME"
    mv "$QUEUE_DIR/pending/$USERNAME/$JOB_ID" "$QUEUE_DIR/done/$USERNAME/"
    echo "Trabajo ejecutado correctamente."
else
    mkdir -p "$QUEUE_DIR/failed/$USERNAME"
    mv "$QUEUE_DIR/pending/$USERNAME/$JOB_ID" "$QUEUE_DIR/failed/$USERNAME/"
    echo "Trabajo falló durante la ejecución."
fi
