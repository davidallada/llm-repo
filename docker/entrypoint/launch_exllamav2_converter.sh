#!/bin/bash

set -e

# Set environment variable to avoid interactive prompts
export DEBIAN_FRONTEND=noninteractive

# Mount the NFS share for storing models
mount -t nfs4 10.69.1.251:/volume1/exllamav2 /mnt/exllamav2

gguf_dir="/mnt/exllamav2/gguf"
exl2_dir="/mnt/exllamav2/exl2"
measurement_json_dir="/mnt/exllamav2/measurement_json"
config_file="/app/tabby_data/converter_config.json"

# Source the virtual environment and set up Hugging Face login
source /venv/bin/activate
if [ -f /app/tabby_data/.tabby_env ]; then
    source /app/tabby_data/.tabby_env
    if [ ! -z "$HF_ACCESS_TOKEN" ]; then
        echo "Attempting to log in to Hugging Face..."
        huggingface-cli login --token $HF_ACCESS_TOKEN || echo "Hugging Face login failed, continuing anyway..."
    fi
else
    echo "No .tabby_env file found, skipping Hugging Face login..."
fi

# Function to convert model name to a formatted string
model_name_to_formatted_string() {
    local model_name=$1
    local first_part="${model_name%%/*}"
    local second_part="${model_name##*/}"
    echo "${first_part}_${second_part}"
}

# Function to download a model in GGUF format
download_model() {
    local model_name=$1
    local formatted_string=$(model_name_to_formatted_string "$model_name")

    # Check if the model already exists
    if [ -d "$gguf_dir/$formatted_string" ]; then
        echo "Model $formatted_string already exists in $gguf_dir. Skipping download."
    else
        echo "Downloading model $formatted_string..."
        if huggingface-cli download "$model_name" --local-dir "/mnt/exllamav2/temp_hf_download/$formatted_string"; then
            mv "/mnt/exllamav2/temp_hf_download/$formatted_string" "$gguf_dir/$formatted_string" && echo "Successfully downloaded using huggingface-cli"
        else
            echo "huggingface-cli download failed, trying hfdownloader..."
            hfdownloader -m "$model_name" -c 10 -s "$gguf_dir"
        fi
    fi
}

# Function to create measurements.json file
process_measurements_json() {
    local model_name=$1
    local formatted_string=$(model_name_to_formatted_string "$model_name")

    if [ -f "$measurement_json_dir/$formatted_string/measurement.json" ]; then
        echo "Measurements for $formatted_string already exist. Skipping processing."
    else
        echo "Processing measurements for $formatted_string..."
        mkdir -p "$measurement_json_dir/$formatted_string"
        python3 /app/exllamav2/convert.py \
            -i "$gguf_dir/$formatted_string" \
            -o "/mnt/temp/$formatted_string-temp" \
            -om "$measurement_json_dir/$formatted_string/measurement.json"
    fi
}

# Function to quantize a GGUF model to EXL2 format
quantize_gguf_to_exl2() {
    local model_name=$1
    local bpw=$2

    local formatted_string=$(model_name_to_formatted_string "$model_name")
    local exl2_path="$exl2_dir/${formatted_string}-${bpw}-bpw"
    local measurement_file="$measurement_json_dir/$formatted_string/measurement.json"

    if [ -d "$exl2_path" ]; then
        echo "EXL2 model ${formatted_string}-${bpw}-bpw already exists. Skipping conversion."
    else
        echo "Converting $formatted_string to EXL2 format with ${bpw} BPW..."

        if [ ! -f "$measurement_file" ]; then
            echo "Measurement file not found. Generating measurements..."
            process_measurements_json "$model_name"
        fi

        python3 /app/exllamav2/convert.py \
            -i "$gguf_dir/$formatted_string" \
            -o "/mnt/temp/${formatted_string}-${bpw}-bpw" \
            -cf "$exl2_path" \
            -b "$bpw" \
            -m "$measurement_file"

        if [ $? -eq 0 ]; then
            echo "Successfully converted $formatted_string to EXL2 format with ${bpw} BPW."
        else
            echo "Failed to convert $formatted_string to EXL2 format with ${bpw} BPW."
        fi
    fi
}

# Function to process a single model configuration
process_model_config() {
    local model_name=$1
    shift
    local bpw_values=("$@")

    local formatted_string=$(model_name_to_formatted_string "$model_name")

    if [ ! -d "$gguf_dir/$formatted_string" ]; then
        download_model "$model_name"
    else
        echo "GGUF model $formatted_string already exists. Skipping download."
    fi

    if [ ! -f "$measurement_json_dir/$formatted_string/measurement.json" ]; then
        process_measurements_json "$model_name"
    else
        echo "Measurements for $formatted_string already exist. Skipping processing."
    fi

    for bpw in "${bpw_values[@]}"; do
        quantize_gguf_to_exl2 "$model_name" "$bpw"
    done
}

# Main execution
if [ ! -f "$config_file" ]; then
    echo "Error: Config file $config_file not found."
    exit 1
fi

jq -c '.model_configs[]' "$config_file" | while read -r config; do
    model_name=$(echo "$config" | jq -r '.model_name')
    readarray -t raw_bpw_values < <(echo "$config" | jq -r '.bpw[]')

    # Convert BPW values to formatted strings with one decimal place
    bpw_values=()
    for bpw in "${raw_bpw_values[@]}"; do
        formatted_bpw=$(awk -v bpw="$bpw" 'BEGIN { printf("%.1f\n", bpw) }' </dev/null)
        bpw_values+=("$formatted_bpw")
    done

    echo "Processing model: $model_name with BPW values: ${bpw_values[*]}"
    process_model_config "$model_name" "${bpw_values[@]}"
done

echo "All models have been processed."
