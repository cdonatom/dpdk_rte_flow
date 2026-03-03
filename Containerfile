ARG BASE_IMAGE=registry.redhat.io/openshift4/dpdk-base-rhel9:v4.20
FROM ${BASE_IMAGE}

ARG DEBUG=true
ENV DEBUG=${DEBUG}

USER root

RUN if [ "$DEBUG" = "true" ]; then \
    microdnf --setopt=tsflags=nodocs update -y && \
#    microdnf --enablerepo='rhel-9-for-x86_64-appstream-debug-rpms' \
    --setopt=tsflags=nodocs -y install \
    gdb dpdk-debuginfo glibc-debuginfo numactl-libs-debuginfo libarchive-debuginfo openssl-libs-debuginfo \
    libacl-debuginfo xz-libs-debuginfo libzstd-debuginfo lz4-libs-debuginfo bzip2-libs-debuginfo \
    zlib-debuginfo libxml2-debuginfo libattr-debuginfo libibverbs-debuginfo libnl3-debuginfo libgcc-debuginfo && \
    microdnf -y clean all --enablerepo='*' \
    ; fi

USER default 
WORKDIR /opt/app-root/src
COPY --chown=default:default src/mac_swap_forward_rte.c .

RUN if [ "$DEBUG" = "true" ]; then \
        echo "Building with debug symbols"; \
        DEBUG_FLAGS="-g"; \
    else \
        echo "Building without debug symbols"; \
        DEBUG_FLAGS=""; \
    fi && \
    gcc mac_swap_forward_rte.c $DEBUG_FLAGS -o mac_swap_forward_rte \
        -O2 -march=x86-64 -msse4.1 -mpopcnt \
        $(pkg-config --cflags --libs libdpdk) \
    && rm mac_swap_forward_rte.c

USER root

RUN setcap cap_sys_resource,cap_ipc_lock,cap_net_raw+ep /opt/app-root/src/mac_swap_forward_rte

USER default

CMD ["sh", "-c", "\
    python3 /usr/local/bin/dpdk-devbind.py --bind=vfio-pci 0000:03:00.0 && \
    /opt/app-root/src/mac_swap_forward_rte -l 0-3 -n 4 -- -p 0x1"]
