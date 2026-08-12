# Multi-stage Dockerfile for YadrenoVPN (builds app from upstream repo)
# Builds a minimal runtime image and clones the upstream repo at build time.

ARG PYTHON_IMAGE=python:3.11-slim
FROM ${PYTHON_IMAGE} AS builder
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies (Pillow needs libjpeg headers etc.)
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libjpeg-dev zlib1g-dev git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Allow overriding upstream repo via build-arg; default points to original project
ARG REPO_URL=https://github.com/plushkinv/YadrenoVPN.git
ARG REPO_REF=main

# Clone upstream source (shallow)
RUN git clone --depth 1 --branch ${REPO_REF} ${REPO_URL} .

# Install Python dependencies into /install
RUN python -m pip install --upgrade pip \
    && python -m pip install --prefix=/install -r requirements.txt

# Final runtime image
FROM ${PYTHON_IMAGE}
ENV PYTHONUNBUFFERED=1

# Runtime libs required by Pillow and related packages
RUN apt-get update \
    && apt-get install -y --no-install-recommends libjpeg62-turbo libfreetype6 libopenjp2-7 ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN adduser --disabled-password --gecos "" yadreno || true

WORKDIR /app

# Ensure app dirs exist and are owned by the runtime user (numeric UID preserved into volumes)
RUN mkdir -p /app/logs /app/database && chown -R yadreno:yadreno /app/logs /app/database || true

# Copy installed Python packages from builder
COPY --from=builder /install /usr/local

# Copy application code from builder
COPY --from=builder /src /app

# Copy entrypoint helper
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Set ownership and switch to non-root user
RUN chown -R yadreno:yadreno /app
USER yadreno

ENV PATH=/usr/local/bin:${PATH}

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["python", "main.py"]
