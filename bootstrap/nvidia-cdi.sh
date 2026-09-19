#!/usr/bin/env bash
# Only needed to switch values/common.yaml to `gpu.mode: cdi`.
#
# The default `wsl` mode bind-mounts /dev/dxg and /usr/lib/wsl/lib and needs
# none of this. CDI is the portable way to ask for a GPU, and worth having
# if this repository ever reconciles a non-WSL host, but podman 4.9.3 (what
# Ubuntu 24.04 ships) does not document CDI selectors in podman-kube-play.
# Verify with `make gpu-check` after running this, before flipping the value.
set -euo pipefail

if ! command -v nvidia-ctk >/dev/null; then
  echo "installing nvidia-container-toolkit"
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y nvidia-container-toolkit
fi

# WSL2 has no /dev/nvidia* nodes; the generator needs to be told.
echo "generating /etc/cdi/nvidia.yaml"
sudo mkdir -p /etc/cdi
sudo nvidia-ctk cdi generate --mode=wsl --output=/etc/cdi/nvidia.yaml

nvidia-ctk cdi list
