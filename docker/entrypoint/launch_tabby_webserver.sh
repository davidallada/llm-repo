#!/bin/bash

# Activate the virtual environment
source /venv/bin/activate

# Read in /app/tabby_data/tabby_model_load_config.json
config_file="/app/tabby_data/tabby_model_load_config.json"

get_model_lists() {
    local config_file="$1"
    local config_key="$2"
    local base_models=()
    local draft_models=()

    # Parse the JSON file and extract model names and draft models for the specified key
    local model_names=$(jq -r ".$config_key[].model_name" "$config_file")
    local draft_model_names=$(jq -r ".$config_key[].draft_model // empty" "$config_file")

    # Create deduplicated lists of models to load
    declare -A base_models_map
    declare -A draft_models_map

    for model in $model_names; do
        if [ ! -z "$model" ]; then
            base_models_map["$model"]=1
        fi
    done

    for model in $draft_model_names; do
        if [ ! -z "$model" ]; then
            draft_models_map["$model"]=1
        fi
    done

    # Convert maps to arrays
    base_models=("${!base_models_map[@]}")
    draft_models=("${!draft_models_map[@]}")

    # Return the arrays
    printf '%s\n' "${base_models[@]}"
    echo "---"  # Delimiter between base models and draft models
    printf '%s\n' "${draft_models[@]}"
}

# Function to efficiently copy models
copy_model() {
    local src="$1"
    local dest="$2"
    local model="$3"
    local type="$4"

    if [ -d "$dest/$model" ]; then
        echo "Updating $type model $model..."
        rclone sync "$src/$model" "$dest/$model" --transfers=12 --checkers=12 --size-only --progress
    else
        echo "Copying new $type model $model..."
        rclone copy "$src/$model" "$dest/$model" --transfers=12 --checkers=12 --progress
    fi
}

load_model_configs() {
    if [ ! -f "$config_file" ]; then
        echo "Error: $config_file not found"
        exit 1
    fi

    # Usage of the function
    readarray -t base_models < <(get_model_lists "$config_file" "model_configs" | sed '/---/q' | sed '$d')
    readarray -t draft_models < <(get_model_lists "$config_file" "model_configs" | sed -n '/---/,$p' | tail -n +2)

    # Now base_models and draft_models are available as arrays
    echo "Base models: ${base_models[*]}"
    echo "Draft models: ${draft_models[*]}"

    # Copy base models and remove unnecessary ones
    echo "Processing base models..."
    for model in "${base_models[@]}"; do
        if [ -n "$model" ] && [ "$model" != "None" ]; then
            copy_model "$EXL2_STORAGE_DIR" "/app/model_directories/base_models" "$model" "base"
            echo "$model" >> /tmp/base_models_to_keep
        else
            echo "Skipping empty or None base model"
        fi
    done

    echo "Removing unnecessary base models..."
    find /app/model_directories/base_models -maxdepth 1 -type d | while read dir; do
        base_dir=$(basename "$dir")
        if [ "$base_dir" != "base_models" ] && ! grep -q "^$base_dir$" /tmp/base_models_to_keep; then
            echo "Removing $dir"
            rm -rf "$dir"
        fi
    done
    rm /tmp/base_models_to_keep

    # Copy draft models and remove unnecessary ones
    echo "Processing draft models..."
    for model in "${draft_models[@]}"; do
        if [ -n "$model" ] && [ "$model" != "None" ]; then
            copy_model "$EXL2_STORAGE_DIR" "/app/model_directories/draft_models" "$model" "draft"
            echo "$model" >> /tmp/draft_models_to_keep
        else
            echo "Skipping empty or None draft model"
        fi
    done

    echo "Removing unnecessary draft models..."
    find /app/model_directories/draft_models -maxdepth 1 -type d | while read dir; do
        base_dir=$(basename "$dir")
        if [ "$base_dir" != "draft_models" ] && ! grep -q "^$base_dir$" /tmp/draft_models_to_keep; then
            echo "Removing $dir"
            rm -rf "$dir"
        fi
    done
    rm /tmp/draft_models_to_keep

    # Load models into respective directories
    echo "Loading models into respective directories..."
    jq -c '.model_configs[]' "$config_file" | while read -r config; do
        model_name=$(echo "$config" | jq -r '.model_name')
        draft_model=$(echo "$config" | jq -r '.draft_model // empty')
        pretty_name=$(echo "$config" | jq -r '.pretty_model_name // empty')
        tabby_config=$(echo "$config" | jq -r '.tabby_config // empty')

        # Use pretty_name for the directory if available, otherwise use model_name
        dir_name="${pretty_name:-$model_name}"
        model_dir="/app/model_directories/models/$dir_name"

        # Create directory for the model
        mkdir -p "$model_dir"

        # Symlink files from base model
        echo "Symlinking files for $model_name to $dir_name..."
        find "/app/model_directories/base_models/$model_name" -type f | while read file; do
            base_name=$(basename "$file")
            if [ "$base_name" != "tabby_config.yml" ]; then
                ln -sf "$file" "$model_dir/$base_name"
            fi
        done

        # Create tabby_config.yml
        echo "Creating tabby_config.yml for $dir_name..."
        {
            if [ ! -z "$tabby_config" ]; then
                echo "$tabby_config" | jq -r 'to_entries | .[] | "\(.key): \(.value)"'
            fi
            if [ ! -z "$draft_model" ]; then
                echo "draft_model:"
                echo "  draft_model_name: $draft_model"
            fi
        } > "$model_dir/tabby_config.yml"

        echo "Finished setting up $dir_name"
    done

    echo "All models have been loaded and configured."
}

load_embedding_model_configs() {
    if [ ! -f "$config_file" ]; then
        echo "Error: $config_file not found"
        exit 1
    fi

    # Usage of the function
    readarray -t base_models < <(get_model_lists "$config_file" "embedding_configs" | sed '/---/q' | sed '$d')
    readarray -t draft_models < <(get_model_lists "$config_file" "embedding_configs" | sed -n '/---/,$p' | tail -n +2)

    # Now base_models and draft_models are available as arrays
    echo "Embedding models: ${base_models[*]}"

    # Copy base models and remove unnecessary ones
    echo "Processing base models..."
    for model in "${base_models[@]}"; do
        if [ -n "$model" ] && [ "$model" != "None" ]; then
            copy_model "$EXL2_STORAGE_DIR" "/app/model_directories/embedding_models" "$model" "embedding"
        else
            echo "Skipping empty or None embedding model"
        fi
    done
}
load_model_configs()
load_embedding_model_configs()
# Start the TabbyAPI server
cd /app/tabbyAPI
./start.sh --gpu-lib cu121

