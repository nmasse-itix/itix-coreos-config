#!/bin/sh

export COREOS_ASSEMBLER_CONTAINER=quay.io/coreos-assembler/coreos-assembler:v0.9.0

function cosa() {
  echo -e "\n>>> cosa" "$@" "\n"
  podman run --rm -ti --security-opt label=disable --privileged --user root                        \
             -v $PWD/cosa/:/srv/ --device /dev/kvm --device /dev/fuse                              \
             --tmpfs /tmp -v /var/tmp:/var/tmp --name cosa -v ${PWD}:/git:ro                       \
             ${COREOS_ASSEMBLER_CONTAINER_RUNTIME_ARGS} ${COREOS_ASSEMBLER_CONTAINER} "$@"
}

set -e
if [ ! -e cosa ]; then
  mkdir -p cosa
  cosa init /git
fi
cosa fetch
cosa build ostree
