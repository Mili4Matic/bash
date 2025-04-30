#!/bin/bash

if [[ "$1" == "--gpus" ]]; then
    NUM_GPUS="$2"
    shift 2
else
    echo "Uso: $0 --gpus [1|2] /ruta/al/archivo.py"
    exit 1
fi

if [ $# -lt 1 ]; then
    echo "Falta el archivo .py a ejecutar."
    exit 1
fi

if [[ "$NUM_GPUS" != "1" && "$NUM_GPUS" != "2" ]]; then
    echo "Número de GPUs inválido. Usa 1 o 2."
    exit 1
fi

SCRIPT_PATH=$(realpath "$1")
SCRIPT_NAME=$(basename "$SCRIPT_PATH")
USERNAME=$(whoami)
QUEUE_DIR="/home/linuxbida/Escritorio/VBoxTools/queue_jobs"
PENDING_DIR="$QUEUE_DIR/pending/$USERNAME"
RUNTIME_DIR="$QUEUE_DIR/runtime"
LOGS_DIR="$QUEUE_DIR/logs"
mkdir -p "$PENDING_DIR" "$RUNTIME_DIR" "$LOGS_DIR"

# Generar ID único del trabajo
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RAND=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 5)
JOB_ID="${USERNAME}_${TIMESTAMP}_${RAND}"

# Crear directorio simbólico para el trabajo
DEST_DIR="$PENDING_DIR/$JOB_ID"
mkdir -p "$DEST_DIR"
ln -s "$SCRIPT_PATH" "$DEST_DIR/$SCRIPT_NAME"

# Añadir a la cola
echo "${JOB_ID}:${NUM_GPUS}" >> "$RUNTIME_DIR/queue_state.txt"
echo "Trabajo añadido con ID: $JOB_ID (requiere $NUM_GPUS GPU/s)"

# Esperar turno
spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
spin_index=0

while true; do
    POSITION=$(grep -n "^$JOB_ID:" "$RUNTIME_DIR/queue_state.txt" | cut -d: -f1)

    if [ -z "$POSITION" ]; then
        echo -e "\nEl trabajo $JOB_ID ha sido removido de la cola inesperadamente."
        exit 1
    fi

    if [ -f "$RUNTIME_DIR/${JOB_ID}.ready" ]; then
        echo -e "\n¡Es tu turno! Ejecutando..."
        break
    else
        printf "\r${spin[$spin_index]} Esperando turno... posición en la cola: $POSITION"
        spin_index=$(( (spin_index + 1) % 10 ))
    fi
    sleep 0.5
done

# Leer GPU_IDs asignados
GPU_IDS=$(cat "$RUNTIME_DIR/${JOB_ID}.ready")
export CUDA_VISIBLE_DEVICES="$GPU_IDS"
echo "GPUs asignadas: $CUDA_VISIBLE_DEVICES"

# Obtener entorno conda del script
REAL_JOB_FILE=$(readlink -f "$DEST_DIR/$SCRIPT_NAME")
REAL_DIR=$(dirname "$REAL_JOB_FILE")

ENV_NAME=$(grep -i "^# *conda_env" "$REAL_JOB_FILE" | sed -E 's/^# *conda_env:?[ ]*//;s/[[:space:]]*$//')

if [ -z "$ENV_NAME" ]; then
    echo "ERROR: No se especificó entorno conda en la cabecera del script."
    exit 1
fi

# Activar entorno conda
source ~/anaconda3/etc/profile.d/conda.sh
conda activate "$ENV_NAME"

# Ejecutar script en tiempo real con log
cd "$REAL_DIR"
stdbuf -oL python -u "$SCRIPT_NAME" | tee "$LOGS_DIR/${JOB_ID}.log"
EXIT_CODE=${PIPESTATUS[0]}

# Desactivar entorno
conda deactivate

# Liberar GPUs
python3 -c "
import json
f = '$RUNTIME_DIR/gpu_status.json'
with open(f) as j:
    status = json.load(j)
for gpu in '$GPU_IDS'.split(','):
    if status.get(gpu) == '$JOB_ID':
        status[gpu] = None
with open(f, 'w') as j:
    json.dump(status, j)
"

# Eliminar .ready
rm -f "$RUNTIME_DIR/${JOB_ID}.ready"

# Mover a done o failed
if [ $EXIT_CODE -eq 0 ]; then
    mkdir -p "$QUEUE_DIR/done/$USERNAME"
    mv "$DEST_DIR" "$QUEUE_DIR/done/$USERNAME/"
    echo -e "\e[32m✅ Trabajo ejecutado correctamente.\e[0m"
else
    mkdir -p "$QUEUE_DIR/failed/$USERNAME"
    mv "$DEST_DIR" "$QUEUE_DIR/failed/$USERNAME/"
    echo -e "\e[31m❌ Trabajo falló durante la ejecución.\e[0m"
fi
