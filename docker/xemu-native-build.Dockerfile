ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bison \
        build-essential \
        ca-certificates \
        ccache \
        cmake \
        curl \
        flex \
        gettext \
        git \
        libasound2-dev \
        libcapstone-dev \
        libepoxy-dev \
        libgbm-dev \
        libgl1-mesa-dev \
        libglib2.0-dev \
        libgtk-3-dev \
        libjpeg-dev \
        libpcap-dev \
        libpixman-1-dev \
        libpng-dev \
        libpulse-dev \
        libsamplerate0-dev \
        libslirp-dev \
        libusb-1.0-0-dev \
        libx11-dev \
        libxcursor-dev \
        libxext-dev \
        libxfixes-dev \
        libxi-dev \
        libxinerama-dev \
        libxkbcommon-dev \
        libxrandr-dev \
        libxrender-dev \
        libxss-dev \
        libxtst-dev \
        libxxf86vm-dev \
        make \
        ninja-build \
        patch \
        pkg-config \
        python3 \
        python3-packaging \
        python3-pip \
        python3-tomli \
        python3-venv \
        python3-yaml \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

ENV NINJA=/usr/bin/ninja
ENV PYTHON=/usr/bin/python3

WORKDIR /workspace
