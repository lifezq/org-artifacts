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

CHANNEL_NAME="$1"
DELAY="$2"
LANGUAGE="$3"
TIMEOUT="$4"
VERBOSE="$5"
ORGCODE="$6"
: ${CHANNEL_NAME:="mychannel"}
: ${DELAY:="3"}
: ${LANGUAGE:="golang"}
: ${TIMEOUT:="10"}
: ${VERBOSE:="false"}
: ${ORGCODE:="4"}
: ${CC_SRC_PATH:="github.com/hyperledger/fabric/examples/chaincode/go/example02/cmd"}
LANGUAGE=`echo "$LANGUAGE" | tr [:upper:] [:lower:]`
COUNTER=1
MAX_RETRY=5

# import utils
. scripts/utils.sh

echo
echo "========= Getting Org"${ORGCODE}" on to your fabric network ========= "
echo
echo "Fetching channel config block from orderer..."
set -x
peer channel fetch 0 $CHANNEL_NAME.block -o orderer1.uniledger.com:7050 -c $CHANNEL_NAME --tls --cafile $ORDERER_CA >&log.txt
res=$?
set +x
cat log.txt
verifyResult $res "Fetching config block from orderer has Failed"


joinChannelWithRetry 0 $ORGCODE
echo "===================== peer0.org"${ORGCODE}" joined channel '$CHANNEL_NAME' ===================== "

echo "Installing chaincode 2.0 on peer0.org"${ORGCODE}"..."
installChaincode 0 $ORGCODE 2.0 upgradecc

sleep 6

instantiateChaincode 0 $ORGCODE 2.0 upgradecc


chaincodeQuery 0 $ORGCODE 100 upgradecc
 
echo
echo "========= Org"${ORGCODE}" is now halfway onto your fabric network ========= "
echo

exit 0
