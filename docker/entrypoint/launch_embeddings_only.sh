#!/bin/bash

# Activate the virtual environment
source /venv/bin/activate

source /app/entrypoint/launch_tabby_webserver.sh

# Read in /app/tabby_data/tabby_model_load_config.json
config_file="/app/tabby_data/tabby_model_load_config.json"

load_embedding_model_configs

# Start the TabbyAPI server
cd /app/tabbyAPI
./start.sh --gpu-lib cu121
