FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV LANG=C.UTF-8
ENV FORCE_UNSAFE_CONFIGURE=1

RUN apt-get update && apt-get install -y \
    # Core build tools
    build-essential gcc g++ make cmake file \
    # Kernel / u-boot build
    bc bison flex libssl-dev libelf-dev \
    device-tree-compiler u-boot-tools \
    # OpenWrt / Tina build system
    libncurses5-dev libncursesw5-dev \
    zlib1g-dev \
    gawk gettext rsync wget curl cpio \
    unzip zip xz-utils liblz4-tool \
    squashfs-tools mtd-utils \
    # Python (build scripts use both 2 and 3)
    python python-dev \
    python3 python3-dev python3-setuptools \
    # Misc
    git perl patch swig \
    libglib2.0-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root/lichee
CMD ["/bin/bash"]
