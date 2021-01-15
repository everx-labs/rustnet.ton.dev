#!/bin/bash -eEx

BEGIN_TIME_STAMP=$(date +%s)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

TMP_DIR=/tmp/$(basename "$0" .sh)_$$
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

set +eE

cd "${DOCKER_COMPOSE_DIR}/ton-node/" && docker-compose stop

if [ "${CLEAN_HOST}" = "yes" ]; then
    docker system prune --all --force --volumes
    docker network create proxy_nw
fi

set -eE

until [ "$(echo "${IntIP}" | grep "\." -o | wc -l)" -eq 3 ]; do
    set +e
    IntIP="$(curl -sS ipv4bot.whatismyipaddress.com)":${ADNL_PORT}
    set -e
    echo "INFO: IntIP = $IntIP"
done

sed -i "s|IntIP.*|IntIP=${IntIP}|g" "${DOCKER_COMPOSE_DIR}/statsd/.env"
cd "${DOCKER_COMPOSE_DIR}/statsd/" && docker-compose pull
cd "${DOCKER_COMPOSE_DIR}/statsd/" && docker-compose up -d

rm -rf "${DOCKER_COMPOSE_DIR}/ton-node/build/ton-node"
cd "${DOCKER_COMPOSE_DIR}/ton-node/build" && git clone --recursive "${TON_NODE_GITHUB_REPO}" ton-node
cd "${DOCKER_COMPOSE_DIR}/ton-node/build/ton-node" && git checkout "${TON_NODE_GITHUB_COMMIT_ID}"

cd "${DOCKER_COMPOSE_DIR}/ton-node/build/ton-node" && git clone --recursive "${TON_NODE_TOOLS_GITHUB_REPO}"
cd "${DOCKER_COMPOSE_DIR}/ton-node/build/ton-node/ton-labs-node-tools" && git checkout "${TON_NODE_TOOLS_GITHUB_COMMIT_ID}"

rm -rf "${DOCKER_COMPOSE_DIR}/ton-node/build/tonos-cli"
cd "${DOCKER_COMPOSE_DIR}/ton-node/build" && git clone --recursive "${TONOS_CLI_GITHUB_REPO}"
cd "${DOCKER_COMPOSE_DIR}/ton-node/build/tonos-cli" && git checkout "${TONOS_CLI_GITHUB_COMMIT_ID}"

rm -f "${DOCKER_COMPOSE_DIR}/ton-node/configs/SafeMultisigWallet.abi.json"
cd "${DOCKER_COMPOSE_DIR}/ton-node/configs"

sed -i "s|NODE_CMD_1.*|NODE_CMD_1=bash|g" "${DOCKER_COMPOSE_DIR}/ton-node/.env"
if [ "${ENABLE_VALIDATE}" = "yes" ]; then
    sed -i "s|NODE_CMD_2.*|NODE_CMD_2=validate|" "${DOCKER_COMPOSE_DIR}/ton-node/.env"
else
    sed -i "s|NODE_CMD_2.*|NODE_CMD_2=novalidate|" "${DOCKER_COMPOSE_DIR}/ton-node/.env"
fi

cd "${DOCKER_COMPOSE_DIR}/ton-node/" && docker-compose up -d
docker ps -a
docker exec --tty rnode "/ton-node/scripts/generate_console_config.sh"
sed -i "s|NODE_CMD_1.*|NODE_CMD_1=normal|g" "${DOCKER_COMPOSE_DIR}/ton-node/.env"
cd "${DOCKER_COMPOSE_DIR}/ton-node/" && docker-compose stop
cd "${DOCKER_COMPOSE_DIR}/ton-node/" && docker-compose up -d

rm -rf "${TMP_DIR}"

END_TIME_STAMP=$(date +%s)
SCRIPT_DURATION=$((END_TIME_STAMP - BEGIN_TIME_STAMP))

echo "INFO: script duration = ${SCRIPT_DURATION} sec."
