FROM registry.redhat.io/openshift4/dpdk-base-rhel8:v4.12

USER default 
WORKDIR /opt/app-root/src
COPY src/mac_swap_forward_rte.c .

RUN gcc mac_swap_forward_rte.c -o mac_swap_forward_rte \
        -O2 -march=x86-64 -msse4.1 -mpopcnt \
        $(pkg-config --cflags --libs libdpdk) \
    && rm mac_swap_forward_rte.c

CMD ["sh", "-c", "\
    python3 /usr/local/bin/dpdk-devbind.py --bind=vfio-pci 0000:03:00.0 && \
    /opt/app-root/src/mac_swap_forward_rte -l 0-3 -n 4 -- -p 0x1 \
"]
