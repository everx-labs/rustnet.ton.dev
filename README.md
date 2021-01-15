# README

This HOWTO contains instructions on how to build and configure a RUST validator node in TON blockchain. The instructions and scripts below were verified on Ubuntu 20.04.
# Getting Started

## 1. System Requirements
| Configuration | CPU (threads) | RAM (GiB) | Storage (GiB) | Network (Gbit/s)|
|---|:---|:---|:---|:---|
| Recommended |48|64|1000|1| 

SSD/NVMe disks are obligatory.

## 2. Prerequisites
### 2.1 Set the Environment
Adjust (if needed) `rustnet.ton.dev/scripts/env.sh`
    
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
	"masterchainblocktime":	1610742179,
	"masterchainblocknumber":	24191,
	"timediff":	5,
	"in_current_vset_p34":	false,
	"in_next_vset_p36":	false
}
```
If the `timediff` parameter equals a few seconds, synchronization is complete.

## 3 Initialize multisignature wallet

### 3.1 Prepare Multisignature Wallet
**Note**: All manual calls of the TONOS-CLI utility should be performed from the `/ton-node/tools` folder in the `rnode` docker container.

Multisignature wallet (or just wallet) is used in validator script to send election requests to the Elector smart contract.

Let `N` be the total number of wallet custodians and `K` the number of minimal confirmations required to execute a wallet transaction.

1. Read [TONOS-CLI documentation](https://docs.ton.dev/86757ecb2/v/0/p/94921e-running-tonos-cli-with-tails-os-and-working-with-multisignature-wallet) (*Deploying Multisignature Wallet to TON blockchain*) and generate seed phrases and public keys for `N - 1`  custodians.
2. Generate wallet address and `Nth` custodian key:
```
    docker exec -it rnode /ton-node/scripts/msig_genaddr.sh
```
Script creates 2 files: `/ton-node/configs/${VALIDATOR_NAME}.addr` and `/ton-node/configs/keys/msig.keys.json`. 
Use public key from `msig.keys.json` as `Nth` custodian public key when you will deploy the wallet.

### 3.2 Initialize multisignature wallet

**Note**: All manual calls of the TONOS-CLI utility should be performed from the `/ton-node/tools` folder in the `rnode` docker container.


Gather all custodians' public keys and deploy wallet using [TONOS-CLI](https://docs.ton.dev/86757ecb2/v/0/p/94921e-running-tonos-cli-with-tails-os-and-working-with-multisignature-wallet) (lookup Deploying Multisignature Wallet to TON blockchain in the document above). Use `K` value as `reqConfirms` deploy parameter.
Make sure that the wallet was deployed at the address saved in `$(hostname -s).addr` file.
