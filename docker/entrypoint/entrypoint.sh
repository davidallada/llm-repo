#!/bin/bash
# Activate the virtual environment
source /venv/bin/activate

# Mount the NFS share for storing models
/app/entrypoint/mount_nfs.sh

cp /app/tabby_data/api_tokens.yml /app/tabbyAPI/api_tokens.yml

# Check the mode passed as the first argument
case "$1" in
    webserver)
        echo "Starting Webserver..."
        # Adjust the command to start your webserver
        cp /app/tabby_data/config.yml /app/tabbyAPI/config.yml
        /app/entrypoint/launch_tabby_webserver.sh
        ;;
    converter)
        echo "Starting Converter..."
        cp /app/tabby_data/config.yml /app/tabbyAPI/config.yml
        # Adjust the command to start your converter
        /app/entrypoint/launch_exllamav2_converter.sh
        ;;
    shell)
        echo "Launching interactive shell..."
        cp /app/tabby_data/config.yml /app/tabbyAPI/config.yml
        /bin/bash
        ;;
    embeddings_only)
        echo "Starting Embeddings Only..."
        cp /app/tabby_data/embeddings_config.yml /app/tabbyAPI/config.yml
        # Add the command to start your embeddings_only process here
        /app/entrypoint/launch_embeddings_only.sh
        ;;
    *)
        echo "Invalid mode. Usage: entrypoint.sh webserver|converter|shell|embeddings_only"
        exit 1
        ;;
esac
