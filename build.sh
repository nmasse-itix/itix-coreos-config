#!/bin/bash

output="$HOME/tmp/itix-coreos"
target="$output/cosa-output"
repo="$output/ostree-repo"
build_repo="$output/ostree-build-repo"
git="$PWD"
# Set the corresponding backend using "rclone config"
s3_bucket="backblaze:itix-ostree"

function message() {
  echo
  echo ">>>" "$@"
  echo
}

function cosa() {
  message "Running cosa $1..."
  set -x
  podman run --rm -ti --security-opt label=disable --privileged --user=root                        \
             -v ${PWD}:/srv/ --device /dev/kvm --device /dev/fuse                                  \
             --tmpfs /tmp -v /var/tmp:/var/tmp --name cosa                                         \
             ${COREOS_ASSEMBLER_CONFIG_GIT:+-v $COREOS_ASSEMBLER_CONFIG_GIT:/srv/src/config/:ro}   \
             ${COREOS_ASSEMBLER_GIT:+-v $COREOS_ASSEMBLER_GIT/src/:/usr/lib/coreos-assembler/:ro}  \
             ${COREOS_ASSEMBLER_CONTAINER_RUNTIME_ARGS}                                            \
             ${COREOS_ASSEMBLER_CONTAINER:-quay.io/coreos-assembler/coreos-assembler:latest} "$@"
  rc=$?
  set +x
  if [ $rc -gt 0 ]; then
    echo 'coreos-assembler failed. Stopping here!'
    exit 1
  fi
  return $rc
}

message "Performing a sanity check on overlay.d..."

need_attention=0
for f in fedora-coreos-config/overlay.d/[0-9][0-9]*; do
  basename="$(basename $f)"
  if [ ! -e "overlay.d/$basename" ]; then
    echo
    echo "WARNING: $f is missing from the top-level overlay.d!"
    echo
    need_attention=1
  fi
done

if [ "$need_attention" == "1" ]; then
  echo "Heads up! Some overlay files from upstream are missing in your top-level git repository. Your build may be incomplete..."
  read -t 5 -p "Press any key to continue."
fi


if [ ! -e "$target" ]; then
  mkdir -p "$target" || exit 1
  cd "$target" || exit 1
  # cosa init skaffolds the folder hierarchy needed for cosa fetch
  # and cosa build. We supply a dummy Git repository here since it is needed.
  # However, we will override it later with the current directory.
  cosa init https://github.com/coreos/fedora-coreos-config.git
else
  cd "$target" || exit 1
fi

export COREOS_ASSEMBLER_CONFIG_GIT="$git"
cosa fetch
cosa build
cosa buildextend-metal
cosa buildextend-metal4k # metal4k is needed to generate the livecd
cosa buildextend-live

message "Extracting generated ostree..."
rm -rf "$build_repo" || exit 1
mkdir -p "$build_repo"
tar -xf "$target"/builds/latest/x86_64/fedora-coreos-*-ostree.x86_64.tar -C "$build_repo"

if [ ! -e "$repo/config" ]; then
  message "Initializing a new ostree repository..."
  mkdir -p "$repo" || exit 1
  ostree init --repo="$repo" --mode=archive || exit 1
fi

message "Importing the new commit..."
ostree --repo="$repo" pull-local "$build_repo" itix/x86_64/coreos/stable || exit 1
message "Generating static delta files (though it may fail if there is no parent commit)..."
ostree --repo="$repo" static-delta generate itix/x86_64/coreos/stable

message "Mirroring the repository to Backblaze B2..."
rclone sync -P "$repo" "$s3_bucket"
