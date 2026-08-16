#!/usr/bin/env bash
set -euo pipefail

install_dependency() {
  local directory="$1"
  local repository="$2"
  local revision="$3"

  rm -rf "$directory"
  mkdir -p "$directory"
  git -C "$directory" init --quiet
  git -C "$directory" remote add origin "$repository"
  git -C "$directory" fetch --quiet --depth 1 origin "$revision"
  git -C "$directory" checkout --quiet --detach FETCH_HEAD
}

install_dependency \
  lib/forge-std \
  https://github.com/foundry-rs/forge-std.git \
  0844d7e1fc5e60d77b68e469bff60265f236c398

install_dependency \
  lib/openzeppelin-contracts \
  https://github.com/OpenZeppelin/openzeppelin-contracts.git \
  69c8def5f222ff96f2b5beff05dfba996368aa79

install_dependency \
  lib/openzeppelin-contracts-upgradeable \
  https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable.git \
  6ed9d6199eca15df84c95a48642e2e7fd5e8e3c7
