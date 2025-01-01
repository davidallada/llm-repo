#!/bin/bash

# Set environment variable to avoid interactive prompts
export DEBIAN_FRONTEND=noninteractive

# Mount the NFS share for storing models
mount -t nfs4 10.69.1.251:/volume1/exllamav2 /mnt/exllamav2

gguf_dir="/mnt/exllamav2/gguf"
exl2_dir="/mnt/exllamav2/exl2"
measurement_json_dir="/mnt/exllamav2/measurement_json"


# Function to convert model name to a formatted string
model_name_to_formatted_string() {
    local model_name=$1
    local first_part="${model_name%%/*}"  # Get the part before the first '/'
    local second_part="${model_name##*/}" # Get the part after the last '/'
    echo "${first_part}_${second_part}"   # Combine with an underscore
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
    # Try huggingface-cli first, fall back to hfdownloader if it fails
    if huggingface-cli download $model_name --local-dir /mnt/exllamav2/temp_hf_download/$formatted_string; then
      mv /mnt/exllamav2/temp_hf_download/$formatted_string $gguf_dir/$formatted_string && echo "Successfully downloaded using huggingface-cli"
    else
      echo "huggingface-cli download failed, trying hfdownloader..."
      hfdownloader -m $model_name -c 10 -s $gguf_dir
    fi
  fi
}

# Function to create measurements.json file
process_measurements_json() {
  local model_name=$1
  local formatted_string=$(model_name_to_formatted_string "$model_name")

  # Check if the measurements.json already exists
  if [ -f "$measurement_json_dir/$formatted_string/measurement.json" ]; then
    echo "Measurements for $formatted_string already exist. Skipping processing."
  else
    echo "Processing measurements for $formatted_string..."
    mkdir -p "$measurement_json_dir/$formatted_string"
    python3 /app/exllamav2/convert.py \
      -i $gguf_dir/$formatted_string \
      -o /mnt/temp/$formatted_string-$bpw-bpw \
      -om $measurement_json_dir/$formatted_string/measurement.json
  fi
}

# Function to quantize a GGUF model to EXL2 format
quantize_gguf_to_exl2() {
    local model_name=$1
    local bpw=$2  # Bits per weight for quantization

    local formatted_string=$(model_name_to_formatted_string "$model_name")
    local exl2_path="$exl2_dir/$formatted_string-$bpw-bpw"
    local measurement_file="$measurement_json_dir/$formatted_string/measurement.json"

    # Check if the EXL2 file already exists
    if [ -d "$exl2_path" ]; then
        echo "EXL2 model $formatted_string-$bpw-bpw already exists. Skipping conversion."
    else
        echo "Converting $formatted_string to EXL2 format with $bpw BPW..."

        # Check if measurement file exists, if not, call process_measurements_json
        if [ ! -f "$measurement_file" ]; then
            echo "Measurement file not found. Generating measurements..."
            process_measurements_json "$model_name"
        fi

        # Run the conversion script
        python3 /app/exllamav2/convert.py \
            -i $gguf_dir/$formatted_string \
            -o /mnt/temp/$formatted_string-$bpw-bpw \
            -cf "$exl2_path" \
            -b $bpw \
            -m "$measurement_file"

        if [ $? -eq 0 ]; then

            # Clean up the temporary directory
            echo "Successfully converted $formatted_string to EXL2 format with $bpw BPW."
        else
            echo "Failed to convert $formatted_string to EXL2 format with $bpw BPW."
        fi
    fi
}

# Function to download a model and then quantize it (if needed)
download_and_quantize() {
    local model_name=$1
    shift
    local bpw_values=($@)

    # First download the model
    download_model $model_name

    local formatted_string=$(model_name_to_formatted_string "$model_name")

    if [ ${#bpw_values[@]} -eq 0 ]; then
        echo "No BPW values provided for $formatted_string. Syncing GGUF to EXL2 directory without conversion."
        mkdir -p "$exl2_dir/$formatted_string"
        rclone sync "$gguf_dir/$formatted_string" "$exl2_dir/$formatted_string" --transfers=12 --checkers=12 --size-only --progress
    else
        # Then create the measurements.json file
        process_measurements_json $model_name

        for bpw in "${bpw_values[@]}"; do
            quantize_gguf_to_exl2 $model_name $bpw
        done
    fi
}

# Function to process the list of models and quantizations
process_model_list() {
    # Check if arguments are provided
    if [ $# -eq 0 ]; then
        echo "Error: No models provided."
        exit 1
    fi

    # Iterate through the arguments
    while [ $# -gt 0 ]; do
        local model_name="$1"
        local bpw_values="$2"

        # Check if model_name is provided
        if [ -n "$model_name" ]; then
            echo "Processing model: $model_name with BPW values: $bpw_values"
            download_and_quantize "$model_name" ${bpw_values//,/ }
        else
            echo "Skipping invalid entry: $model_name $bpw_values"
        fi

        # Shift to the next pair of arguments
        shift 2
        if [ $? -ne 0 ]; then
            echo "Error: Odd number of arguments. Each model must have corresponding BPW values (or empty string for no conversion)."
            exit 1
        fi
    done
}

# Main execution
if [ $# -eq 0 ]; then
    echo "Usage: $0 <ModelName/Version> <BPW1,BPW2,BPW3...> [<ModelName/Version> <BPW1,BPW2,BPW3...> ...]"
    echo "Example: $0 Qwen/QwQ-32B-preview 4.0,6.0,8.0 AnotherModel/ModelName ''"
    exit 1
fi

process_model_list "$@"
