#!/bin/bash

QUEUE_DIR="/home/queue_jobs"
PENDING_DIR="$QUEUE_DIR/pending"
DONE_DIR="$QUEUE_DIR/done"
FAILED_DIR="$QUEUE_DIR/failed"
LOCK_FILE="$QUEUE_DIR/.queue.lock"

mkdir -p "$PENDING_DIR" "$DONE_DIR" "$FAILED_DIR"

if [ -f "$LOCK_FILE" ]; then
    echo "Otro proceso ya está ejecutando un trabajo. Salimos."
    exit 1
fi

touch "$LOCK_FILE"

for job_dir in $(find "$PENDING_DIR" -mindepth 2 -maxdepth 2 -type d | sort); do
    if [ ! -d "$job_dir" ]; then
        continue
    fi

    echo "Procesando trabajo: $job_dir"

    # Encontrar el symlink
    job_link=$(find "$job_dir" -maxdepth 1 -type l -name "*.py" | head -n 1)

    if [ -z "$job_link" ]; then
        echo "ERROR: No se encontró symlink en $job_dir. Moviendo a failed."
        username=$(basename $(dirname "$job_dir"))
        mkdir -p "$FAILED_DIR/$username"
        mv "$job_dir" "$FAILED_DIR/$username/"
        continue
    fi

    # Resolver el symlink
    real_job=$(readlink -f "$job_link")
    if [ ! -f "$real_job" ]; then
        echo "ERROR: El archivo real $real_job no existe. Moviendo a failed."
        username=$(basename $(dirname "$job_dir"))
        mkdir -p "$FAILED_DIR/$username"
        mv "$job_dir" "$FAILED_DIR/$username/"
        continue
    fi

    env_name=$(head -n 1 "$real_job" | sed -n 's/^# *conda_env: *//p')

    if [ -z "$env_name" ]; then
        echo "ERROR: El trabajo $(basename "$real_job") no especifica entorno conda. Moviendo a failed."
        username=$(basename $(dirname "$job_dir"))
        mkdir -p "$FAILED_DIR/$username"
        mv "$job_dir" "$FAILED_DIR/$username/"
        continue
    fi

    echo "Activando entorno: $env_name"
    source ~/anaconda3/etc/profile.d/conda.sh
    conda activate "$env_name"

    job_dir_real=$(dirname "$real_job")
    cd "$job_dir_real"

    echo "Ejecutando $(basename "$real_job") en $job_dir_real"
    python "$(basename "$real_job")"
    exit_code=$?

    conda deactivate

    username=$(basename $(dirname "$job_dir"))

    if [ $exit_code -eq 0 ]; then
        echo "Trabajo $(basename "$real_job") ejecutado correctamente."
        mkdir -p "$DONE_DIR/$username"
        mv "$job_dir" "$DONE_DIR/$username/"
    else
        echo "Trabajo $(basename "$real_job") falló durante la ejecución."
        mkdir -p "$FAILED_DIR/$username"
        mv "$job_dir" "$FAILED_DIR/$username/"
    fi

    echo "-----------------------------------"

done

rm -f "$LOCK_FILE"
