#!/bin/bash -eE

set -o pipefail

DEBUG=yes

# Stake value for fixed staking mode (not applicable for dynamic staking mode)
STAKE="$1"
LOCK_FILE="/tmp/validator.lock"

exit_and_clean() {
    EXIT_CODE="$1"
    EXIT_LINE="$2"
    rm -f ${LOCK_FILE}
    [ "${EXIT_CODE}" -eq 0 ] && rm -rf "${TMP_DIR}"
    echo "INFO: script exited (exit code: ${EXIT_CODE}, script line: ${EXIT_LINE})"
    echo "INFO: $(basename "$0") END $(date +%s) / $(date)"
    exit "${EXIT_CODE}"
}

init_env() {
    if [ "$DEBUG" = "yes" ]; then
        set -x
    fi

    if [ -f ${LOCK_FILE} ]; then
        echo "ERROR: ${LOCK_FILE} exists, exiting..."
        exit 1
    else
        touch ${LOCK_FILE}
    fi

    trap 'exit_and_clean $? $LINENO' SIGHUP SIGINT SIGQUIT SIGTERM ERR

    echo "INFO: $(basename "$0") BEGIN $(date +%s) / $(date)"

    TMP_DIR=/tmp/$(basename "$0" .sh)_$$
    rm -rf "${TMP_DIR}"
    mkdir -p "${TMP_DIR}"

    # Check for startup pause
    T_FROM_START=$(($(date +%s) - $(stat -c %Y /proc)))
    if [ "${T_FROM_START}" -le 119 ]; then
        echo "INFO: Container started less then 120s ago. Only ${T_FROM_START} s passed."
        exit_and_clean 1 $LINENO
    fi

    # Balance reminder (keep it after staking for fees)
    BALANCE_REMINDER="100" # tokens
    # https://test.ton.org/Validator-HOWTO.txt
    # Here <max-factor> = 3 is the maximum ratio allowed between your stake and the minimal validator stake in the elected
    # validator group. In this way you can be sure that your stake will be no more than 3 times the smallest stake, so
    # the workload of your validator is at most 3 times the lowest one. If your stake is too large compared to the stakes
    # of other validators, then it will be clipped to this value (3 times the smallest stake), and the remainder will be
    # returned to you (i.e., to the controlling smart contract of your validator) immediately after elections.
    MAX_FACTOR=${MAX_FACTOR:-3}
    ELECTOR_ADDR="-1:3333333333333333333333333333333333333333333333333333333333333333"
    TON_BUILD_DIR=""

    if [ "${RUST_NET_ENABLE}" = "yes" ]; then
        TON_NODE_ROOT="/ton-node"
        UTILS_DIR="${TON_NODE_ROOT}/tools"
        CONFIGS_DIR="${TON_NODE_ROOT}/configs"
        KEYS_DIR="${CONFIGS_DIR}/keys"
        WORK_DIR="${UTILS_DIR}"
        MSIG_ADDR_FILE="${CONFIGS_DIR}/${VALIDATOR_NAME}.addr"
        if [ "${DEPOOL_ENABLE}" = "yes" ]; then
            DEPOOL_ADDR_FILE="${CONFIGS_DIR}/depool.addr"
        fi
    else
        UTILS_DIR="/utils"
        KEYS_DIR="/keys"
        WORK_DIR="/validation"
        CONFIGS_DIR="${WORK_DIR}/configs"
        LITE_SERVER_IP_ADDRESS="127.0.0.1"
        LITE_SERVER_PORT="3030"
        CRYPTO_LIBS="/crypto/lib:/crypto/smartcont"
        mkdir -p "${CONFIGS_DIR}"
        MSIG_ADDR_FILE="${KEYS_DIR}/${VALIDATOR_NAME}.addr"
        if [ "${DEPOOL_ENABLE}" = "yes" ]; then
            DEPOOL_ADDR_FILE="${KEYS_DIR}/depool.addr"
        fi
    fi

    # Supported values: fift, solidity
    ELECTOR_TYPE=${ELECTOR_TYPE:-solidity}
    TONOS_CLI_RETRIES=${TONOS_CLI_RETRIES:-5}
    # This file is created during 1st script run in dynamic staking mode
    # It is used to split the initial amount of tokens among 2 election cycles
    VALIDATOR_INIT_BALANCE_FILE=${KEYS_DIR}/validator_init_balance.txt
}

check_env() {
    if [ ! -f "${MSIG_ADDR_FILE}" ]; then
        echo "ERROR: ${MSIG_ADDR_FILE} does not exist"
        exit_and_clean 1 $LINENO
    fi

    MSIG_ADDR=$(cat "${MSIG_ADDR_FILE}")
    echo "INFO: MSIG_ADDR = ${MSIG_ADDR}"

    if [ -z "${MSIG_ADDR}" ]; then
        echo "ERROR: MSIG_ADDR is empty"
        exit_and_clean 1 $LINENO
    fi

    if [ "${DEPOOL_ENABLE}" = "yes" ] && [ ! -f "${DEPOOL_ADDR_FILE}" ]; then
        echo "ERROR: ${DEPOOL_ADDR_FILE} does not exist"
        exit_and_clean 1 $LINENO
    fi

    if [ "${DEPOOL_ENABLE}" = "yes" ]; then
        DEPOOL_ADDR=$(cat "${KEYS_DIR}/depool.addr")

        if [ -z "${DEPOOL_ADDR}" ]; then
            echo "ERROR: DEPOOL_ADDR is empty"
            exit_and_clean 1 $LINENO
        fi

        echo "INFO: DEPOOL_ADDR = ${DEPOOL_ADDR}"
    fi

    if [ "${RUST_NET_ENABLE}" = "yes" ]; then
        if [ ! -f ${CONFIGS_DIR}/console.json ]; then
            echo "ERROR: ${CONFIGS_DIR}/console.json does not exist"
            exit_and_clean 1 $LINENO
        fi
    fi

    if [ ! -f "${KEYS_DIR}/msig.keys.json" ]; then
        echo "ERROR: ${KEYS_DIR}/msig.keys.json does not exist"
        exit_and_clean 1 $LINENO
    fi

    if [ ! -f "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" ]; then
        cd ${CONFIGS_DIR} && wget https://raw.githubusercontent.com/tonlabs/ton-labs-contracts/master/solidity/safemultisig/SafeMultisigWallet.abi.json
    fi

    if [ "${ELECTOR_TYPE}" = "solidity" ] && [ ! -f ${CONFIGS_DIR}/Elector.abi.json ]; then
        echo "ERROR: ${CONFIGS_DIR}/Elector.abi.json does not exist"
        exit_and_clean 1 $LINENO
    fi

    cd ${WORK_DIR}
    if [ "${DEPOOL_ENABLE}" = "yes" ]; then
        ${UTILS_DIR}/tonos-cli config --url "${SDK_URL}" --retries "${TONOS_CLI_RETRIES}" \
            --addr "${DEPOOL_ADDR}" --wallet "${MSIG_ADDR}" --keys "${KEYS_DIR}/msig.keys.json"
    else
        ${UTILS_DIR}/tonos-cli config --url "${SDK_URL}" --retries "${TONOS_CLI_RETRIES}"
    fi

    if [ "$DEBUG" = "yes" ]; then
        echo "DEBUG: ${WORK_DIR}/tonos-cli.conf.json BEGIN"
        cat ${WORK_DIR}/tonos-cli.conf.json
        echo "DEBUG: ${WORK_DIR}/tonos-cli.conf.json END"
    fi

    if [ "${TONOS_CLI_RETRIES}" != "$(jq .retries ${WORK_DIR}/tonos-cli.conf.json)" ]; then
        echo "ERROR: wrong configuration in ${WORK_DIR}/tonos-cli.conf.json"
        exit_and_clean 1 $LINENO
    fi
}

recover_stake() {
    if [ "${DEPOOL_ENABLE}" = "yes" ]; then
        echo "WARNING: recover_stake() is not applicable for depool validator"
        return
    fi

    MSIG_ADDR_HEX="0x$(echo "${MSIG_ADDR}" | cut -d ':' -f 2)"

    case ${ELECTOR_TYPE} in
    "fift")
        RECOVER_AMOUNT_HEX=$(${UTILS_DIR}/tonos-cli runget ${ELECTOR_ADDR} compute_returned_stake "${MSIG_ADDR_HEX}" 2>&1 | grep "Result:" | awk -F'"' '{print $2}')
        ;;
    "solidity")
        RECOVER_AMOUNT_HEX=$(${UTILS_DIR}/tonos-cli run ${ELECTOR_ADDR} compute_returned_stake "{\"wallet_addr\":\"${MSIG_ADDR_HEX}\"}" --abi ${CONFIGS_DIR}/Elector.abi.json 2>&1 | grep "value0" | awk '{print $2}' | tr -d '"')
        ;;
    *)
        echo "ERROR: unknown ELECTOR_TYPE (${ELECTOR_TYPE})"
        exit_and_clean 1 $LINENO
        ;;
    esac

    RECOVER_AMOUNT=$(printf "%d" "${RECOVER_AMOUNT_HEX}")
    echo "INFO: RECOVER_AMOUNT = ${RECOVER_AMOUNT}"

    if [ -z "${RECOVER_AMOUNT}" ]; then
        echo "ERROR: RECOVER_AMOUNT is empty"
        exit_and_clean 1 $LINENO
    fi

    if [ "${RECOVER_AMOUNT}" != "0" ]; then
        if [ "${RUST_NET_ENABLE}" = "yes" ]; then
            ${UTILS_DIR}/console -C ${CONFIGS_DIR}/console.json -c recover_stake
            mv recover-query.boc "${TMP_DIR}/recover-query.boc"
        else
            "${TON_BUILD_DIR}/crypto/fift" -I "${CRYPTO_LIBS}" -s recover-stake.fif "${TMP_DIR}/recover-query.boc"
        fi

        if [ -f "${TMP_DIR}/recover-query.boc" ]; then
            RECOVER_QUERY_BOC=$(base64 --wrap=0 "${TMP_DIR}/recover-query.boc")
        else
            echo "ERROR: ${TMP_DIR}/recover-query.boc does not exist"
            exit_and_clean 1 $LINENO
        fi

        if [ -z "${RECOVER_QUERY_BOC}" ]; then
            echo "ERROR: RECOVER_QUERY_BOC is empty"
            exit_and_clean 1 $LINENO
        fi

        echo "INFO: tonos-cli submitTransaction attempt..."
        set -x
        if ! "${UTILS_DIR}/tonos-cli" call "${MSIG_ADDR}" submitTransaction \
            "{\"dest\":\"${ELECTOR_ADDR}\",\"value\":\"1000000000\",\"bounce\":true,\"allBalance\":false,\"payload\":\"${RECOVER_QUERY_BOC}\"}" \
            --abi "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" \
            --sign "${KEYS_DIR}/msig.keys.json"; then
            echo "INFO: tonos-cli submitTransaction attempt... FAIL"
            exit_and_clean 1 $LINENO
        else
            echo "INFO: tonos-cli submitTransaction attempt... PASS"
            date +"INFO: %F %T Recover of ${RECOVER_AMOUNT} tokens requested"
            exit_and_clean 0 $LINENO
        fi
        set +x
    else
        echo "INFO: nothing to recover"
    fi
}

prepare_for_elections() {
    case ${ELECTOR_TYPE} in
    "fift")
        ACTIVE_ELECTION_ID_HEX=$(${UTILS_DIR}/tonos-cli runget ${ELECTOR_ADDR} active_election_id 2>&1 | grep "Result:" | awk -F'"' '{print $2}')
        ;;
    "solidity")
        ACTIVE_ELECTION_ID_HEX=$(${UTILS_DIR}/tonos-cli run ${ELECTOR_ADDR} active_election_id {} --abi ${CONFIGS_DIR}/Elector.abi.json 2>&1 | grep "value0" | awk '{print $2}' | tr -d '"')
        ;;
    *)
        echo "ERROR: unknown ELECTOR_TYPE (${ELECTOR_TYPE})"
        exit_and_clean 1 $LINENO
        ;;
    esac

    if [ -z "${ACTIVE_ELECTION_ID_HEX}" ]; then
        echo "ERROR: failed to get active elections ID"
        exit_and_clean 1 $LINENO
    fi

    ACTIVE_ELECTION_ID=$(printf "%d" "${ACTIVE_ELECTION_ID_HEX}")
    echo "INFO: ACTIVE_ELECTION_ID = ${ACTIVE_ELECTION_ID}"

    if [ "${ACTIVE_ELECTION_ID}" = "0" ]; then
        date +"INFO: %F %T No current elections"
        exit_and_clean 0 $LINENO
    fi

    # Create ${ELECTIONS_WORK_DIR}/stop-election if you would like to forcibly stop validator script logic
    if [ -f "${ELECTIONS_WORK_DIR}/stop-election" ]; then
        exit_and_clean 0 $LINENO
    fi

    ELECTIONS_WORK_DIR="${KEYS_DIR}/elections/${ACTIVE_ELECTION_ID}"
    mkdir -p "${ELECTIONS_WORK_DIR}"

    if [ "${DEPOOL_ENABLE}" = "yes" ]; then
        "${UTILS_DIR}/tonos-cli" depool --addr "${DEPOOL_ADDR}" events >"${ELECTIONS_WORK_DIR}/events.txt" 2>&1

        set +eE
        set +o pipefail
        ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT=$(grep "^{" "${ELECTIONS_WORK_DIR}/events.txt" | grep electionId |
            jq ".electionId" | head -1 | tr -d '"' | xargs printf "%d\n")
        echo "INFO: ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT = ${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}"

        if [ "${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}" = "${ACTIVE_ELECTION_ID}" ]; then
            PROXY_ADDR_FROM_DEPOOL_EVENT=$(grep "^{" "${ELECTIONS_WORK_DIR}/events.txt" | grep electionId |
                jq ".proxy" | head -1 | tr -d '"')
            echo "INFO: PROXY_ADDR_FROM_DEPOOL_EVENT = ${PROXY_ADDR_FROM_DEPOOL_EVENT}"
            if [ -z "${PROXY_ADDR_FROM_DEPOOL_EVENT}" ]; then
                echo "ERROR: unable to detect PROXY_ADDR_FROM_DEPOOL_EVENT"
                exit_and_clean 1 $LINENO
            fi
        else
            echo "ERROR: ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT (${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}) does not match to ACTIVE_ELECTION_ID (${ACTIVE_ELECTION_ID})"
            echo "Verify '${UTILS_DIR}/tonos-cli depool --addr ${DEPOOL_ADDR} events' output"
            exit_and_clean 1 $LINENO
        fi
        set -eE
        set -o pipefail
    fi

    if [ -f "${ELECTIONS_WORK_DIR}/active-election-id-submitted" ]; then
        ACTIVE_ELECTION_ID_SUBMITTED=$(cat "${ELECTIONS_WORK_DIR}/active-election-id-submitted")
        if [ "${ACTIVE_ELECTION_ID_SUBMITTED}" = "${ACTIVE_ELECTION_ID}" ]; then
            date +"INFO: %F %T Elections ${ACTIVE_ELECTION_ID} already submitted"
            exit_and_clean 0 $LINENO
        fi
    fi
}

create_elector_request() {
    ELECTIONS_ARTEFACTS_CREATED="0"
    if [ -f "${ELECTIONS_WORK_DIR}/election-artefacts-created" ] &&
        [ "${ACTIVE_ELECTION_ID}" = "$(cat "${ELECTIONS_WORK_DIR}/election-artefacts-created")" ]; then
        ELECTIONS_ARTEFACTS_CREATED="1"
    fi

    if [ "${ELECTIONS_ARTEFACTS_CREATED}" = "0" ]; then
        GLOBAL_CONFIG_15_RAW=$(${UTILS_DIR}/tonos-cli getconfig 15 2>&1)
        ELECTIONS_END_BEFORE=$(echo "$GLOBAL_CONFIG_15_RAW" | grep "elections_end_before" | awk '{print $2}' | tr -d ',')
        ELECTIONS_START_BEFORE=$(echo "$GLOBAL_CONFIG_15_RAW" | grep "elections_start_before" | awk '{print $2}' | tr -d ',')
        STAKE_HELD_FOR=$(echo "$GLOBAL_CONFIG_15_RAW" | grep "stake_held_for" | awk '{print $2}' | tr -d ',')
        VALIDATORS_ELECTED_FOR=$(echo "$GLOBAL_CONFIG_15_RAW" | grep "validators_elected_for" | awk '{print $2}' | tr -d ',')
        echo "INFO: ELECTIONS_START_BEFORE = ${ELECTIONS_START_BEFORE}"
        echo "INFO: ELECTIONS_END_BEFORE = ${ELECTIONS_END_BEFORE}"
        echo "INFO: STAKE_HELD_FOR = ${STAKE_HELD_FOR}"
        echo "INFO: VALIDATORS_ELECTED_FOR = ${VALIDATORS_ELECTED_FOR}"

        ELECTION_START="${ACTIVE_ELECTION_ID}"
        # TODO: duration may be reduced - to be checked
        ELECTION_STOP=$((ACTIVE_ELECTION_ID + 1000 + ELECTIONS_START_BEFORE + ELECTIONS_END_BEFORE + STAKE_HELD_FOR + VALIDATORS_ELECTED_FOR))

        if [ "${DEPOOL_ENABLE}" = "yes" ]; then
            VALIDATOR_MSIG_ADDR="${PROXY_ADDR_FROM_DEPOOL_EVENT}"
        else
            VALIDATOR_MSIG_ADDR="${MSIG_ADDR}"
        fi

        if [ "${RUST_NET_ENABLE}" = "yes" ]; then
            jq ".wallet_id = \"${VALIDATOR_MSIG_ADDR}\"" ${CONFIGS_DIR}/console.json >"${TMP_DIR}/console.json"
            cp "${TMP_DIR}/console.json" ${CONFIGS_DIR}/console.json
            ${UTILS_DIR}/console -C ${CONFIGS_DIR}/console.json -c "election-bid ${ELECTION_START} ${ELECTION_STOP}"
            mv validator-query.boc "${ELECTIONS_WORK_DIR}"
        else
            if [ -f "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-election-key" ]; then
                echo "ERROR: ${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-election-key already exists"
                exit_and_clean 1 $LINENO
            fi

            "${TON_BUILD_DIR}/validator-engine-console/validator-engine-console" \
                -k "${KEYS_DIR}/client" \
                -p "${KEYS_DIR}/server.pub" \
                -a ${LITE_SERVER_IP_ADDRESS}:${LITE_SERVER_PORT} \
                -c "newkey" -c "quit" \
                &>"${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-election-key"

            ELECTION_KEY=$(grep "created new key" "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-election-key" | awk '{print $4}')
            echo "INFO: ELECTION_KEY = ${ELECTION_KEY}"

            if [ -z "${ELECTION_KEY}" ]; then
                echo "ERROR: ELECTION_KEY is empty"
                exit_and_clean 1 $LINENO
            fi

            if [ -f "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-election-adnl-key" ]; then
                echo "ERROR: ${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-election-adnl-key already exists"
                exit_and_clean 1 $LINENO
            fi

            "${TON_BUILD_DIR}/validator-engine-console/validator-engine-console" \
                -k "${KEYS_DIR}/client" \
                -p "${KEYS_DIR}/server.pub" \
                -a ${LITE_SERVER_IP_ADDRESS}:${LITE_SERVER_PORT} \
                -c "newkey" -c "quit" \
                &>"${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-election-adnl-key"

            ELECTION_ADNL_KEY=$(grep "created new key" "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-election-adnl-key" | awk '{print $4}')
            echo "INFO: ELECTION_ADNL_KEY = ${ELECTION_ADNL_KEY}"

            if [ -z "${ELECTION_ADNL_KEY}" ]; then
                echo "ERROR: ELECTION_ADNL_KEY is empty"
                exit_and_clean 1 $LINENO
            fi

            "${TON_BUILD_DIR}/validator-engine-console/validator-engine-console" \
                -k "${KEYS_DIR}/client" \
                -p "${KEYS_DIR}/server.pub" \
                -a ${LITE_SERVER_IP_ADDRESS}:${LITE_SERVER_PORT} \
                -c "addpermkey ${ELECTION_KEY} ${ELECTION_START} ${ELECTION_STOP}" \
                -c "addtempkey ${ELECTION_KEY} ${ELECTION_KEY} ${ELECTION_STOP}" \
                -c "addadnl ${ELECTION_ADNL_KEY} 0" \
                -c "addvalidatoraddr ${ELECTION_KEY} ${ELECTION_ADNL_KEY} ${ELECTION_STOP}" \
                -c "quit"

            "${TON_BUILD_DIR}/crypto/fift" \
                -I ${CRYPTO_LIBS} \
                -s validator-elect-req.fif "${VALIDATOR_MSIG_ADDR}" "${ELECTION_START}" "${MAX_FACTOR}" "${ELECTION_ADNL_KEY}" "${ELECTIONS_WORK_DIR}/validator-to-sign.bin" \
                &>"${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-request-dump"

            REQUEST=$(sed --silent 2p "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-request-dump")
            echo "INFO: REQUEST = $REQUEST"

            if [ -z "${REQUEST}" ]; then
                echo "ERROR: REQUEST is empty"
                exit_and_clean 1 $LINENO
            fi

            "${TON_BUILD_DIR}/validator-engine-console/validator-engine-console" \
                -k "${KEYS_DIR}/client" \
                -p "${KEYS_DIR}/server.pub" \
                -a ${LITE_SERVER_IP_ADDRESS}:${LITE_SERVER_PORT} \
                -c "exportpub ${ELECTION_KEY}" \
                -c "sign ${ELECTION_KEY} $REQUEST" \
                &>"${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-request-dump1"

            PUBLIC_KEY=$(grep "got public key" "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-request-dump1" | awk '{print $4}')
            SIGNATURE=$(grep "got signature" "${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-request-dump1" | awk '{print $3}')

            echo "INFO: PUBLIC_KEY = ${PUBLIC_KEY}"
            echo "INFO: SIGNATURE = ${SIGNATURE}"

            if [ -z "${PUBLIC_KEY}" ]; then
                echo "ERROR: PUBLIC_KEY is empty"
                exit_and_clean 1 $LINENO
            fi

            if [ -z "${SIGNATURE}" ]; then
                echo "ERROR: SIGNATURE is empty"
                exit_and_clean 1 $LINENO
            fi

            "${TON_BUILD_DIR}/crypto/fift" \
                -I ${CRYPTO_LIBS} \
                -s validator-elect-signed.fif "${VALIDATOR_MSIG_ADDR}" "${ELECTION_START}" "${MAX_FACTOR}" "${ELECTION_ADNL_KEY}" "${PUBLIC_KEY}" "${SIGNATURE}" "${ELECTIONS_WORK_DIR}/validator-query.boc" \
                &>"${ELECTIONS_WORK_DIR}/${VALIDATOR_NAME}-request-dump2"
        fi

        echo "${ACTIVE_ELECTION_ID}" >"${ELECTIONS_WORK_DIR}/election-artefacts-created"
    else
        echo "WARNING: election artefacts already created"
    fi

    if [ -f "${ELECTIONS_WORK_DIR}/validator-query.boc" ]; then
        VALIDATOR_QUERY_BOC=$(base64 --wrap=0 "${ELECTIONS_WORK_DIR}/validator-query.boc")
    else
        echo "ERROR: ${ELECTIONS_WORK_DIR}/validator-query.boc does not exist"
        rm -f "${ELECTIONS_WORK_DIR}/election-artefacts-created"
        exit_and_clean 1 $LINENO
    fi

    if [ -z "${VALIDATOR_QUERY_BOC}" ]; then
        echo "ERROR: VALIDATOR_QUERY_BOC is empty"
        exit_and_clean 1 $LINENO
    fi
}

submit_stake() {
    VALIDATOR_ACTUAL_BALANCE_NANO=$(${UTILS_DIR}/tonos-cli account "${MSIG_ADDR}" | grep balance | awk '{print $2}') # in nano tokens
    VALIDATOR_ACTUAL_BALANCE=$((VALIDATOR_ACTUAL_BALANCE_NANO / 1000000000))                                         # in tokens
    echo "INFO: ${MSIG_ADDR} VALIDATOR_ACTUAL_BALANCE = ${VALIDATOR_ACTUAL_BALANCE} tokens"

    if [ -z "${VALIDATOR_ACTUAL_BALANCE}" ]; then
        echo "ERROR: VALIDATOR_ACTUAL_BALANCE is empty"
        exit_and_clean 1 $LINENO
    fi

    if [ "${DEPOOL_ENABLE}" = "yes" ]; then
        if [ "${VALIDATOR_ACTUAL_BALANCE_NANO}" -le 1000000000 ]; then
            echo "ERROR: not enough tokens in ${MSIG_ADDR} wallet"
            echo "INFO: VALIDATOR_ACTUAL_BALANCE_NANO = ${VALIDATOR_ACTUAL_BALANCE_NANO}"
            exit_and_clean 1 $LINENO
        fi

        echo "INFO: tonos-cli submitTransaction attempt..."
        set -x
        if ! "${UTILS_DIR}/tonos-cli" call "${MSIG_ADDR}" submitTransaction \
            "{\"dest\":\"${DEPOOL_ADDR}\",\"value\":\"1000000000\",\"bounce\":true,\"allBalance\":false,\"payload\":\"${VALIDATOR_QUERY_BOC}\"}" \
            --abi "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" \
            --sign "${KEYS_DIR}/msig.keys.json"; then
            echo "INFO: tonos-cli submitTransaction attempt... FAIL"
            exit_and_clean 1 $LINENO
        else
            echo "INFO: tonos-cli submitTransaction attempt... PASS"
            date +"INFO: %F %T prepared for elections ${ACTIVE_ELECTION_ID}"
            echo "${ACTIVE_ELECTION_ID}" >"${ELECTIONS_WORK_DIR}/active-election-id-submitted"
        fi
        set +x
    else
        if [ -z "${STAKE}" ]; then
            echo "INFO: dynamic staking mode"
            if [ ! -f "${VALIDATOR_INIT_BALANCE_FILE}" ]; then
                echo "${VALIDATOR_ACTUAL_BALANCE}" >"${VALIDATOR_INIT_BALANCE_FILE}"
                # Split actual balance for 2 election cycles
                STAKE=$(((VALIDATOR_ACTUAL_BALANCE - BALANCE_REMINDER) / 2))
            else
                if [ ${VALIDATOR_ACTUAL_BALANCE} = "$(cat "${VALIDATOR_INIT_BALANCE_FILE}")" ]; then
                    # 1st stake has not yet been submitted
                    # Split actual balance for 2 election cycles
                    STAKE=$(((VALIDATOR_ACTUAL_BALANCE - BALANCE_REMINDER) / 2))
                else
                    # It is 2nd (and further) staking iteration - use all available tokens (except the reminder for fees)
                    STAKE=$((VALIDATOR_ACTUAL_BALANCE - BALANCE_REMINDER))
                fi
            fi
        else
            echo "INFO: fixed staking mode"
        fi

        echo "INFO: STAKE = $STAKE tokens"

        if [ $STAKE -ge ${VALIDATOR_ACTUAL_BALANCE} ]; then
            echo "ERROR: not enough tokens in ${MSIG_ADDR} wallet"
            echo "INFO: VALIDATOR_ACTUAL_BALANCE = ${VALIDATOR_ACTUAL_BALANCE}"
            exit_and_clean 1 $LINENO
        fi

        MIN_STAKE=$(${UTILS_DIR}/tonos-cli getconfig 17 | grep min_stake | awk '{print $2}' | tr -d '"' | tr -d ',') # in nanotokens
        MIN_STAKE=$((MIN_STAKE / 1000000000))                                                                        # in tokens
        echo "INFO: MIN_STAKE = ${MIN_STAKE} tokens"

        if [ -z "${MIN_STAKE}" ]; then
            echo "ERROR: MIN_STAKE is empty"
            exit_and_clean 1 $LINENO
        fi

        if [ "$STAKE" -lt "${MIN_STAKE}" ]; then
            echo "ERROR: STAKE ($STAKE tokens) is less than MIN_STAKE (${MIN_STAKE} tokens)"
            exit_and_clean 1 $LINENO
        fi

        NANOSTAKE=$("${UTILS_DIR}/tonos-cli" convert tokens "$STAKE" | tail -1)
        echo "INFO: NANOSTAKE = $NANOSTAKE nanotokens"

        if [ -z "${NANOSTAKE}" ]; then
            echo "ERROR: NANOSTAKE is empty"
            exit_and_clean 1 $LINENO
        fi

        echo "INFO: tonos-cli submitTransaction attempt..."
        set -x
        if ! "${UTILS_DIR}/tonos-cli" call "${MSIG_ADDR}" submitTransaction \
            "{\"dest\":\"${ELECTOR_ADDR}\",\"value\":\"${NANOSTAKE}\",\"bounce\":true,\"allBalance\":false,\"payload\":\"${VALIDATOR_QUERY_BOC}\"}" \
            --abi "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" \
            --sign "${KEYS_DIR}/msig.keys.json"; then
            echo "INFO: tonos-cli submitTransaction attempt... FAIL"
            exit_and_clean 1 $LINENO
        else
            echo "INFO: tonos-cli submitTransaction attempt... PASS"
            date +"INFO: %F %T prepared for elections ${ACTIVE_ELECTION_ID}"
            echo "${ACTIVE_ELECTION_ID}" >"${ELECTIONS_WORK_DIR}/active-election-id-submitted"
        fi
        set +x
    fi
}

#==============================================================================
#                                Main
#==============================================================================
init_env
check_env
if [ "${DEPOOL_ENABLE}" != "yes" ]; then
    recover_stake
fi
prepare_for_elections
create_elector_request
submit_stake
exit_and_clean 0 $LINENO
