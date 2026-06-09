FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git build-essential fakeroot libncurses5-dev libssl-dev ccache \
    dfu-util u-boot-tools device-tree-compiler mtools \
    bc python3 python-is-python3 cpio zip unzip rsync file wget curl \
    xz-utils bzip2 gzip gawk sed make gcc g++ flex bison perl \
    libelf-dev libglib2.0-dev libtinfo5 locales \
 && rm -rf /var/lib/apt/lists/*
