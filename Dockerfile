FROM ubuntu:focal

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
        gcc-aarch64-linux-gnu \
        gcc-arm-none-eabi \
        git \
        less \
        libncurses5 \
        libncurses5-dev \
        libssl-dev \
        locales \
        mtools \
        nano \
        python \
        python3 \
        python3-dev \
        python3-distutils \
        python-pyelftools \
        rename \
        sed \
        swig \
        tar \
    && locale-gen en_US.utf8

# Clean up apt
RUN apt-get clean \
   && rm -rf /var/lib/apt/lists/* /tmp/*

CMD ["/bin/bash"]
