FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        bash \
        bison \
        build-essential \
        ca-certificates \
        ccache \
        clang \
        cmake \
        curl \
        file \
        flex \
        gettext \
        git \
        libasound2-dev \
        libcapstone-dev \
        libcurl4-gnutls-dev \
        libdecor-0-dev \
        libdrm-dev \
        libegl1-mesa-dev \
        libepoxy-dev \
        libfdt-dev \
        libgbm-dev \
        libgl1-mesa-dev \
        libglib2.0-dev \
        libgnutls28-dev \
        libgtk-3-dev \
        libjpeg-dev \
        libpcap-dev \
        libpipewire-0.3-dev \
        libpixman-1-dev \
        libpng-dev \
        libpulse-dev \
        libsamplerate0-dev \
        libslirp-dev \
        libudev-dev \
        libusb-1.0-0-dev \
        libvte-2.91-dev \
        libwayland-dev \
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
        make \
        ninja-build \
        nettle-dev \
        perl \
        pkg-config \
        python3 \
        python3-pip \
        python3-venv \
        python3-yaml \
        sed \
        tar \
        unzip \
        wayland-protocols \
        xz-utils \
        zlib1g-dev \
        zstd && \
    rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/meson && \
    /opt/meson/bin/pip install --upgrade pip && \
    /opt/meson/bin/pip install meson==1.9.0 tomli

ENV PATH="/opt/meson/bin:${PATH}"
ENV NINJA="/usr/bin/ninja"
ENV PYTHON="/usr/bin/python3"

WORKDIR /workspace
