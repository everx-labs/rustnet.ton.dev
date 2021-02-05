# README

This HOWTO contains instructions on how to build and configure a RUST validator node in TON blockchain. The instructions and scripts below were verified on Ubuntu 20.04.
# Getting Started

## 1. System Requirements
| Configuration | CPU (threads) | RAM (GiB) | Storage (GiB) | Network (Gbit/s)|
|---|:---|:---|:---|:---|
| Minimum |48|64|1000|1| 

SSD/NVMe disks are obligatory.

## 2. Prerequisites
### 2.1 Set the Environment
Adjust (if needed) `rustnet.ton.dev/scripts/env.sh`

Set `export DEPOOL_ENABLE=yes` in `env.sh` for a depool validator (an elector request is sent to a depool from a validator multisignature wallet).

Set `export DEPOOL_ENABLE=no` in `env.sh` for a direct staking validator (an elector request is sent from a multisignature wallet directly to the elector).
    
    cd rustnet.ton.dev/scripts/
    . ./env.sh 

### 2.2 Install Dependencies
`install_deps.sh` script supports Ubuntu OS only.

    ./install_deps.sh 
Install and configure Docker according to the [official documentation](https://docs.docker.com/engine/install/ubuntu/). 

## 3. Deploy RUST Validator Node
Do this step when the network is launched.
Deploy the node:

    ./deploy.sh
  
Wait until the node is synced with the masterchain. Depending on network throughput this step may take significant time (up to several hours).

Use the following command to check if the node is synced:

    docker exec -it rnode /ton-node/tools/console -C /ton-node/configs/console.json --cmd getstats

Script output example:
```
tonlabs console 0.1.0
COMMIT_ID: 0569a2bbb18c1ce966b1ac21cdf193dbd3c5817b
BUILD_DATE: 2021-01-15 19:11:52 +0000
COMMIT_DATE: 2021-01-15 16:26:58 +0300
GIT_BRANCH: master
{
  "masterchainblocktime": 1610742179,
  "masterchainblocknumber": 24191,
  "timediff": 5,
  "in_current_vset_p34": false,
  "in_next_vset_p36": false
}
```
If the `timediff` parameter equals a few seconds, synchronization is complete.

## 3 Configure validator multisignature wallet and depool

- For direct staking validator it is necessary to create and deploy a validator [SafeMultisig](https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity/safemultisig) wallet  in `-1` chain and place 2 files on the validator node: `/ton-node/configs/${VALIDATOR_NAME}.addr` (validator multisignature wallet address in form `-1:XXX...XXX`) and `/ton-node/configs/keys/msig.keys.json` (validator multisignature custodian's keypair). If there are more than 1 custodian make sure each transactions sent by the validator are confirmed by required amount of custodians.
  
  Documentation: [Multisignature Wallet Management in TONOS-CLI](https://docs.ton.dev/86757ecb2/p/94921e-multisignature-wallet-management-in-tonos-cli)
- For a depool validator it is necessary to create and deploy a validator [SafeMultisig](https://github.com/tonlabs/ton-labs-contracts/tree/master/solidity/safemultisig) wallet in `0` chain, a depool in `0` chain and place 3 files on the validator node: `/ton-node/configs/${VALIDATOR_NAME}.addr` (validator multisignature wallet address in form `0:XXX...XXX`), `/ton-node/configs/keys/msig.keys.json` (validator multisignature custodian's keypair) and `/ton-node/configs/depool.addr` (depool address in form `0:XXX...XXX`)

  Documentation: [Run DePool v3](https://docs.ton.dev/86757ecb2/p/04040b-run-depool-v3)

The script generating validator election requests (directly through multisig wallet, or through depool, depending on the setting selected on step 2.1) will run regularly, once the necessary addresses and keys are provided.
