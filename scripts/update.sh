#!/bin/bash -eEx

BEGIN_TIME_STAMP=$(date +%s)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

rm -rf "${DOCKER_COMPOSE_DIR}/ton-node/build/ton-node"
cd "${DOCKER_COMPOSE_DIR}/ton-node/build" && git clone --recursive "${TON_NODE_GITHUB_REPO}" ton-node
cd "${DOCKER_COMPOSE_DIR}/ton-node/build/ton-node" && git checkout "${TON_NODE_GITHUB_COMMIT_ID}"

rm -rf "${DOCKER_COMPOSE_DIR}/ton-node/build/ton-labs-node-tools"
cd "${DOCKER_COMPOSE_DIR}/ton-node/build" && git clone --recursive "${TON_NODE_TOOLS_GITHUB_REPO}"
cd "${DOCKER_COMPOSE_DIR}/ton-node/build/ton-labs-node-tools" && git checkout "${TON_NODE_TOOLS_GITHUB_COMMIT_ID}"

rm -rf "${DOCKER_COMPOSE_DIR}/ton-node/build/tonos-cli"
cd "${DOCKER_COMPOSE_DIR}/ton-node/build" && git clone --recursive "${TONOS_CLI_GITHUB_REPO}"
cd "${DOCKER_COMPOSE_DIR}/ton-node/build/tonos-cli" && git checkout "${TONOS_CLI_GITHUB_COMMIT_ID}"

cd "${DOCKER_COMPOSE_DIR}/ton-node/"
docker-compose build --no-cache
docker-compose down && docker-compose up -d

END_TIME_STAMP=$(date +%s)
SCRIPT_DURATION=$((END_TIME_STAMP - BEGIN_TIME_STAMP))

echo "INFO: script duration = ${SCRIPT_DURATION} sec."
