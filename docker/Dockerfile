FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV LANGUAGE=en_US:en

RUN apt-get update && apt-get install -y \
    git build-essential fakeroot libncurses5-dev libssl-dev ccache \
    dfu-util u-boot-tools device-tree-compiler mtools \
    bc python3 python-is-python3 cpio zip unzip rsync file wget curl \
    xz-utils bzip2 gzip gawk sed make gcc g++ flex bison perl \
    libelf-dev libglib2.0-dev libtinfo5 locales \
    libgmp-dev libmpfr-dev libmpc-dev \
    x11-utils \
 && locale-gen en_US.UTF-8 \
 && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/xilinx-shims

RUN printf '%s\n' \
    '#!/bin/bash' \
    'exec /opt/Xilinx/Vitis/2023.2/bin/loader -exec rdi_xsct "$@"' \
    > /usr/local/xilinx-shims/xsct \
 && chmod +x /usr/local/xilinx-shims/xsct

RUN printf '%s\n' \
    '#!/bin/bash' \
    'source /opt/Xilinx/Vivado/2023.2/settings64.sh' \
    'source /opt/Xilinx/Vitis/2023.2/settings64.sh' \
    'export PATH=/usr/local/xilinx-shims:/opt/Xilinx/Vitis/2023.2/gnu/aarch32/lin/gcc-arm-none-eabi/bin:$PATH' \
    > /xilinx-2023.2-settings.sh \
 && chmod +x /xilinx-2023.2-settings.sh
