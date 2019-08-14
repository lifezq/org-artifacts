#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# This script is designed to be run in the orgcli container as the
# second step of the EYFN tutorial. It joins the org peers to the
# channel previously setup in the BYFN tutorial and install the
# chaincode as version 2.0 on peer0.org.
#

echo
echo "========= Getting Org on to your first network ========= "
echo
CHANNEL_NAME="$1"
DELAY="$2"
LANGUAGE="$3"
TIMEOUT="$4"
VERBOSE="$5"
: ${CHANNEL_NAME:="mychannel"}
: ${DELAY:="3"}
: ${LANGUAGE:="golang"}
: ${TIMEOUT:="10"}
: ${VERBOSE:="false"}
LANGUAGE=`echo "$LANGUAGE" | tr [:upper:] [:lower:]`
COUNTER=1
MAX_RETRY=5

CC_SRC_PATH="github.com/hyperledger/fabric/examples/chaincode/go/example02/cmd"
if [ "$LANGUAGE" = "node" ]; then
        CC_SRC_PATH="/opt/gopath/src/github.com/hyperledger/fabric/peer/chaincode_node"
fi

# import utils
. scripts/utils.sh

echo "Fetching channel config block from orderer..."
set -x
peer channel fetch 0 $CHANNEL_NAME.block -o orderer1.uniledger.com:7050 -c $CHANNEL_NAME --tls --cafile $ORDERER_CA >&log.txt
res=$?
set +x
cat log.txt
verifyResult $res "Fetching config block from orderer has Failed"


joinChannelWithRetry 0 4
echo "===================== peer0.org joined channel '$CHANNEL_NAME' ===================== "

echo "Installing chaincode 2.0 on peer0.org..."
installChaincode 0 4 2.0 upgradecc

sleep 6

instantiateChaincode 0 4 2.0 upgradecc


chaincodeQuery 0 4 100 upgradecc
 
echo
echo "========= Org is now halfway onto your first network ========= "
echo

exit 0
