FROM registry.redhat.io/openshift4/dpdk-base-rhel9:v4.20

USER default 
WORKDIR /opt/app-root/src
COPY src/mac_swap_forward_rte.c .

RUN gcc mac_swap_forward_rte.c -o mac_swap_forward_rte \
        -O2 -march=x86-64 -msse4.1 -mpopcnt \
        $(pkg-config --cflags --libs libdpdk) \
    && rm mac_swap_forward_rte.c

USER root

RUN setcap cap_sys_resource,cap_ipc_lock,cap_net_raw+ep /opt/app-root/src/mac_swap_forward_rte

USER default

CMD ["sh", "-c", "\
    python3 /usr/local/bin/dpdk-devbind.py --bind=vfio-pci 0000:03:00.0 && \
    /opt/app-root/src/mac_swap_forward_rte -l 0-3 -n 4 -- -p 0x1"]
