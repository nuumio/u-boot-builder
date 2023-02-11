FROM ubuntu:22.04

ENV DEBIAN_FRONTEND 'noninteractive'
ENV XZ_DEFAULTS '-T0'

# Everything, and something extra, needed for building ATF
# and U-Boot for (at least) rk3399 and rk3328. (Can also be
# used for building BSP U-Boot if one _really_ wants.)
RUN set -ex \
    && apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        bc \
        bison \
        build-essential \
        ca-certificates \
        curl \
        device-tree-compiler \
        dosfstools \
        flex \
        gawk \
        gcc-10-aarch64-linux-gnu \
        gcc-10-arm-linux-gnueabihf \
        gcc-aarch64-linux-gnu \
        gcc-arm-linux-gnueabihf \
        gcc-arm-none-eabi \
        git \
        gnutls-dev \
        less \
        libncurses5 \
        libncurses5-dev \
        libssl-dev \
        locales \
        mtools \
        nano \
        python2 \
        python3 \
        python3-dev \
        python3-distutils \
        python3-setuptools \
        python3-pyelftools \
        rename \
        sed \
        swig \
        tar \
        uuid-dev \
    && locale-gen en_US.utf8

# Clean up apt
RUN apt-get clean \
   && rm -rf /var/lib/apt/lists/* /tmp/*

CMD ["/bin/bash"]
