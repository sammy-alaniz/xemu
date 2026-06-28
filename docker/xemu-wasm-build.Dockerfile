ARG EMSCRIPTEN_IMAGE=emscripten/emsdk:latest
FROM ${EMSCRIPTEN_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        cmake \
        ninja-build \
        patch \
        pkg-config \
        python3 \
        python3-packaging \
        python3-yaml \
        python3-venv && \
    rm -rf /var/lib/apt/lists/*

ENV NINJA=/usr/bin/ninja
ENV PYTHON=/usr/bin/python3

WORKDIR /workspace
