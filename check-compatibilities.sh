#!/usr/bin/env bash
set -euo pipefail

versionsFile=changes-8e18c70.json
nixpkgsPath=${NIXPKGS_PATH:-}
if [[ ! -e $nixpkgsPath ]]; then
    echo "Please set NIXPKGS_PATH"
    exit 1
fi
if ! git -C "$nixpkgsPath" diff --quiet; then
    echo "$nixpkgsPath has changes"
    exit 1
fi
if ! git -C "$nixpkgsPath" ls-files --other --directory --exclude-standard | sed q1 >/dev/null; then
    echo "$nixpkgsPath has untracked files"
    exit 1
fi

cleanup() {
    origCode=$?
    set +e
    sudo systemctl start nscd
    extra-container destroy tmp
    git -C "$nixpkgsPath" switch -f master &>/dev/null
    git -C "$nixpkgsPath" clean -fd >/dev/null
    exit $origCode
}
trap "cleanup" EXIT

read -d '' tmpstr <<'EOF' || :
{
  containers.tmp = {
    extra.addressPrefix = "10.30.0";
    config = { pkgs, config, lib, ... }: {
      documentation.enable = false;
      environment.variables.PAGER = "cat";
    };
  };
}
EOF
extra-container create -s -E "$tmpstr"
sudo systemctl stop nscd

build() {(
    set -euo pipefail
    version=$1
    index=$2
    attr=$3
    rev=$(jq -r ".\"$version\"[$index]".rev "$versionsFile")
    git -C "$nixpkgsPath" checkout $rev &>/dev/null
    nix build --no-link --json --impure -f "$nixpkgsPath" "$attr" | jq -r '.[].outputs | .[]'
    # nix eval --impure -f "$nixpkgsPath" "$attr"
)}
check() {(
    set -euo pipefail
    modulesVersion=$1
    modulesIndex=$2
    binVersion=$3
    binIndex=$4
    echo "modules: $modulesVersion (#$modulesIndex), client: $binVersion (#$binIndex)"
    modules=$(build $modulesVersion $modulesIndex systemd)
    bin=$(build $binVersion $binIndex glibc.bin)
    [[ $bin && $modules ]] || exit 1
    LD_LIBRARY_PATH=$modules/lib $bin/bin/getent hosts tmp || {
        echo '(failed)'
    }
)}

# '2.33  0' is the latest glibc drv with version 2.33
# '2.33 -1' is the earliest drv
# Results:
# c = core dump
# - = error, no result
check 2.33  0   2.33  0 # ok
check 2.33  0   2.33 -1 # ok
check 2.33 -1   2.33  0 # ok
check 2.33  0   2.32  0 # -
check 2.33  0   2.31  0 # -
check 2.33  0   2.30  0 # c
check 2.32  0   2.31  0 # -
check 2.32  0   2.32 -1 # ok
check 2.32 -1   2.32  0 # ok
check 2.32  0   2.30  0 # c
check 2.30  0   2.30 -1 # ok
check 2.30 -1   2.30  0 # ok
check 2.30  0   2.27  0 # c
check 2.31  0   2.30  0 # c
check 2.31  0   2.27  0 # c
check 2.27  0   2.27 -1 # ok
check 2.27 -1   2.27  0 # ok

#
# info

jq -r keys[] "$versionsFile"
# 2.27
# 2.30
# 2.31
# 2.32
# 2.33

jq -r '."2.27" | length' "$versionsFile"
jq -er '."2.33"[0].rev' "$versionsFile"
jq -er '."2.33"[-1].rev' "$versionsFile"
jq -er '."2.33"' "$versionsFile"
