#!/bin/bash -eE

DEBUG=${DEBUG:-no}

if [ "$DEBUG" = "yes" ]; then
    set -x
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
export SCRIPT_DIR
SRC_TOP_DIR=$(cd "${SCRIPT_DIR}/../" && pwd -P)
export SRC_TOP_DIR
export DOCKER_COMPOSE_DIR="${SRC_TOP_DIR}/docker-compose"
export ENABLE_VALIDATE="yes"
export CLEAN_HOST=${CLEAN_HOST:-yes}
export COMPOSE_HTTP_TIMEOUT=120 # in sec, 60 sec - default
HOSTNAME=$(hostname -f)
export TON_NODE_GITHUB_REPO="https://github.com/tonlabs/ton-labs-node.git"
export TON_NODE_GITHUB_COMMIT_ID="377a6c77d35d8d3f4132dd547afd1e9cfcb8ba23"
export TON_NODE_TOOLS_GITHUB_REPO="https://github.com/tonlabs/ton-labs-node-tools.git"
export TON_NODE_TOOLS_GITHUB_COMMIT_ID="master"
export TONOS_CLI_GITHUB_REPO="https://github.com/tonlabs/tonos-cli.git"
export TONOS_CLI_GITHUB_COMMIT_ID="master"
export DEPOOL_ENABLE="yes"
