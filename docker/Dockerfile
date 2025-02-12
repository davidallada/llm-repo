# syntax=docker/dockerfile:1.4

# Set a default value for VERSION
ARG VERSION=debug

# Stage 1: Build environment
FROM nvidia/cuda:12.1.0-devel-ubuntu22.04 AS tabbyapi-exllamav2-builder-image

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    VERSION=${VERSION}

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    wget \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y python3.12 python3.12-venv python3.12-dev \
    && apt-get install -y ninja-build \
    && rm -rf /var/lib/apt/lists/*

# Clone necessary repositories
WORKDIR /app
RUN git clone --depth 1 https://github.com/turboderp/exllamav2 /app/exllamav2 && \
    git clone --depth 1 https://github.com/theroyallab/tabbyAPI /app/tabbyAPI && \
    git clone --depth 1 https://github.com/turboderp/exui /app/exui && \
    git clone --depth 1 https://github.com/bodaay/HuggingFaceModelDownloader /app/HuggingFaceModelDownloader

# Create virtual environment in /venv
RUN python3.12 -m venv /venv
RUN ln -s /venv /app/tabbyAPI/venv
ENV PATH="/venv/bin:$PATH"

# Install pip and packages within the virtual environment
RUN /venv/bin/pip install --upgrade pip setuptools wheel && \
    /venv/bin/pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 && \
    /venv/bin/pip install pandas ninja fastparquet safetensors sentencepiece pygments websockets regex pynvml exllamav2 Flask waitress && \
    /venv/bin/pip install -U "huggingface_hub[cli]" && \
    MAX_JOBS=4 /venv/bin/pip install flash-attn --no-build-isolation && \
    /venv/bin/pip install fastapi pydantic PyYAML progress uvicorn jinja2 colorlog loguru transformers jupyterlab-vim polars


# Install hfdownloader
# Wget go for hfdownloader
RUN wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz && tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
ENV PATH="$PATH:/usr/local/go/bin"
RUN cd  /app/HuggingFaceModelDownloader && /app/HuggingFaceModelDownloader/BuildLinuxAmd64.sh && \
    chmod +x /app/HuggingFaceModelDownloader/output/hfdownloader_linux_amd64_* && \
    mv /app/HuggingFaceModelDownloader/output/hfdownloader_linux_amd64_* /usr/local/bin/hfdownloader && cd /app

# Install tabbyAPI dependencies
RUN /bin/bash -c "source /venv/bin/activate && \
    cd /app/tabbyAPI && \
    /app/tabbyAPI/start.sh --update-deps --gpu-lib cu121 && \
    pip install .[extras]"

# Stage 2: Runtime environment
FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04 AS tabbyapi-exllamav2-builder-image-runtime

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    VERSION=${VERSION}

# Install runtime dependencies including Python 3.12
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    nfs-common \
    rsync \
    rclone \
    vim \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.12 as the default Python version
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 \
    && update-alternatives --set python3 /usr/bin/python3.12

# Copy only necessary files from tabbyapi-exllamav2-builder-image
COPY --from=tabbyapi-exllamav2-builder-image /venv /venv
COPY --from=tabbyapi-exllamav2-builder-image /app/exllamav2 /app/exllamav2
COPY --from=tabbyapi-exllamav2-builder-image /app/tabbyAPI /app/tabbyAPI
COPY --from=tabbyapi-exllamav2-builder-image /app/exui /app/exui
COPY --from=tabbyapi-exllamav2-builder-image /usr/local/bin/hfdownloader /usr/local/bin/hfdownloader

# Create symlink for consistency
RUN ln -s /venv /app/tabbyAPI/venv

ENV PATH="/venv/bin:$PATH"

# Create necessary directories
RUN mkdir -p /mnt/exllamav2/{gguf,exl2} /mnt/converter /mnt/temp/{download,gguf,exl2,temp} /app/tabby_data /app/model_directories/{base_models,models,draft_models,embedding_models,loras}

WORKDIR /app

COPY entrypoint /app/entrypoint

RUN chmod +x /app/entrypoint/*.sh

# Expose ports for Jupyter Lab and exllamav2
EXPOSE 8888 5000

# Add LABELs near the end of your Dockerfile
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.title="TabbyAPI ExLlamaV2"
LABEL org.opencontainers.image.description="TabbyAPI with ExLlamaV2 support"
LABEL org.opencontainers.image.source="https://github.com/yourusername/yourrepository"

# Set the entrypoint to activate the virtual environment and then execute the command
ENTRYPOINT ["/app/entrypoint/entrypoint.sh"]

# Set a default command (optional)
CMD ["webserver"]
