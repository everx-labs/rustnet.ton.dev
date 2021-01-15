#!/bin/bash -eEx

export TON_NODE_ROOT_DIR="/ton-node"
export TON_NODE_CONFIGS_DIR="${TON_NODE_ROOT_DIR}/configs"
export TON_NODE_TOOLS_DIR="${TON_NODE_ROOT_DIR}/tools"
export TON_NODE_SCRIPTS_DIR="${TON_NODE_ROOT_DIR}/scripts"
export TON_NODE_LOGS_DIR="${TON_NODE_ROOT_DIR}/logs"

echo "INFO: R-Node startup..."

echo "INFO: NETWORK_TYPE = ${NETWORK_TYPE}"
echo "INFO: DEPLOY_TYPE = ${DEPLOY_TYPE}"
echo "INFO: CONFIGS_PATH = ${CONFIGS_PATH}"
echo "INFO: \$1 = $1"
echo "INFO: \$2 = $2"

NODE_EXEC="${TON_NODE_ROOT_DIR}/ton_node_kafka"
if [ "${TON_NODE_ENABLE_KAFKA}" -ne 1 ]; then
    echo "INFO: Kafka disabled"
    NODE_EXEC="${TON_NODE_ROOT_DIR}/ton_node_no_kafka"
else
    echo "INFO: Kafka enabled"
fi

function f_get_ton_global_config_json() {
    curl -sS "https://raw.githubusercontent.com/tonlabs/rustnet.ton.dev/main/configs/ton-global.config.json" -o "${TON_NODE_CONFIGS_DIR}/ton-global.config.json"
}

function f_iscron() {
    apt update && apt install -y cron

    if ! grep "validator_msig\|validator_depool" /etc/crontab >/dev/null 2>&1; then
        {
            echo "RUST_NET_ENABLE=yes"
            echo "STAKE=$STAKE"
            echo "VALIDATOR_NAME=${VALIDATOR_NAME}"
            echo "SDK_URL=${SDK_URL}"
            echo "ELECTOR_TYPE=${ELECTOR_TYPE}"
            echo "@hourly  root  ${TON_NODE_SCRIPTS_DIR}/validator_msig.sh \${STAKE} >>${TON_NODE_LOGS_DIR}/validator_msig.log 2>&1"
        } >>/etc/crontab
    fi

    chmod +x ${TON_NODE_TOOLS_DIR}/validator_msig.sh
    pgrep cron >/dev/null || cron
}

# main
f_get_ton_global_config_json

if [ "$1" = "bash" ]; then
    tail -f /dev/null
else
    [ "$2" = "validate" ] && f_iscron
    cd ${TON_NODE_ROOT_DIR}
    # shellcheck disable=SC2086
    exec $NODE_EXEC --configs "${CONFIGS_PATH}" ${TON_NODE_EXTRA_ARGS} >>${TON_NODE_LOGS_DIR}/output.log 2>&1
fi
