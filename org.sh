#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script extends the Hyperledger Fabric By Your First Network by
# adding a third organization to the network previously setup in the
# BYFN tutorial.
#

################ run example #################
#### ./org.sh up -c mychannel -t 5 -d 3 l golang -i 1.2.1 -v false -o 4
################ run example #################

# If BYFN wasn't run abort
if [ ! -d crypto-config -o ! -d channel-artifacts ]; then
  echo
  echo "ERROR: Please, generate first."
  echo
  exit 1
fi

# prepending $PWD/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
export PATH=${PWD}/../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}
export VERBOSE=false

CC_SRC_PATH="github.com/hyperledger/fabric/examples/chaincode/go/example02/cmd"
if [ "$LANGUAGE" = "node" ]; then
        CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/chaincode_example02/node/"
fi

# Print the usage message
function printHelp () {
  echo "Usage: "
  echo "  org.sh up|down|restart|generate [-c <channel name>] [-t <timeout>] [-d <delay>] [-f <docker-compose-file>] [-s <dbtype>]"
  echo "  org.sh -h|--help (print this message)"
  echo "    <mode> - one of 'up', 'down', 'restart' or 'generate'"
  echo "      - 'up' - bring up the network with docker-compose up"
  echo "      - 'down' - clear the network with docker-compose down"
  echo "      - 'restart' - restart the network"
  echo "      - 'generate' - generate required certificates and genesis block"
  echo "    -c <channel name> - channel name to use (defaults to \"mychannel\")"
  echo "    -o <org code> - org code (defaults to \"4\")"
  echo "    -t <timeout> - CLI timeout duration in seconds (defaults to 10)"
  echo "    -d <delay> - delay duration in seconds (defaults to 3)"
  echo "    -l <language> - the chaincode language: golang (default) or node"
  echo "    -i <imagetag> - the tag to be used to launch the network (defaults to \"latest\")"
  echo "    -v - verbose mode"
  echo
  echo "Typically, one would first generate the required certificates and "
  echo "genesis block, then bring up the network. e.g.:"
  echo
  echo "	org.sh generate -c mychannel"
  echo "	org.sh up -c mychannel -s couchdb"
  echo "	org.sh up -l node"
  echo "	org.sh down -c mychannel"
  echo
  echo "Taking all defaults:"
  echo "	org.sh generate"
  echo "	org.sh up"
  echo "	org.sh down"
}

# Ask user for confirmation to proceed
function askProceed () {
  read -p "Continue? [Y/n] " ans
  case "$ans" in
    y|Y|"" )
      echo "proceeding ..."
    ;;
    n|N )
      echo "exiting..."
      exit 1
    ;;
    * )
      echo "invalid response"
      askProceed
    ;;
  esac
}

# Obtain CONTAINER_IDS and remove them
# TODO Might want to make this optional - could clear other containers
function clearContainers () {
  CONTAINER_IDS=$(docker ps -aq)
  if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
    echo "---- No containers available for deletion ----"
  else
    docker rm -f $CONTAINER_IDS
  fi
}

# Delete any images that were generated as a part of this setup
# specifically the following images are often left behind:
# TODO list generated image naming patterns
function removeUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images|awk '($1 ~ /dev-peer.*.mycc.*/) {print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    echo "---- No images available for deletion ----"
  else
    docker rmi -f $DOCKER_IMAGE_IDS
  fi
}

# Generate the needed certificates, the genesis block and start the network.
function networkUp () {
  # generate artifacts if they don't exist
  #if [ ! -d "crypto-config" ]; then
    #generateCerts
    #generateChannelArtifacts
    #createConfigTx
  #fi
  # start cli
  IMAGE_TAG=${IMAGETAG} docker-compose -f $COMPOSE_FILE up -d 2>&1
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to start cli network"
    exit 1
  fi

  createConfigTx

  echo
  echo "###############################################################"
  echo "############### Have Org peers join network ##################"
  echo "###############################################################"
  docker exec cli ./scripts/step2org.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE $ORGCODE
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to have Org peers join network"
    exit 1
  fi

  exit 0

  echo
  echo "###############################################################"
  echo "##### Upgrade chaincode to have Org peers on the network #####"
  echo "###############################################################"
  docker exec cli ./scripts/step3org.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to add Org peers on network"
    exit 1
  fi
  # finish by running the test
  docker exec cli ./scripts/testorg.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to run test"
    exit 1
  fi
}

# Tear down running network
function networkDown () {
  docker-compose -f $COMPOSE_FILE down --volumes --remove-orphans
  # Don't remove containers, images, etc if restarting
  if [ "$MODE" != "restart" ]; then
    #Cleanup the chaincode containers
    clearContainers
    #Cleanup images
    removeUnwantedImages
    # remove orderer block and other channel configuration transactions and certs
    rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config ./crypto-config/ channel-artifacts/org.json
  fi
}

# Use the CLI container to create the configuration transaction needed to add
# Org to the network
function createConfigTx () {
  echo
  echo "###############################################################"
  echo "####### Generate and submit config tx to add Org #############"
  echo "###############################################################"
  configtxgen -printOrg Org4MSP > ./channel-artifacts/org.json
  docker cp core.yaml cli:/opt/gopath/src/github.com/hyperledger/fabric/peer/
  docker exec cli ln -s crypto/peerOrganizations/org1.uniledger.com/users/Admin@org1.uniledger.com/msp ./msp
  docker exec cli ln -s crypto/peerOrganizations/org1.uniledger.com/users/Admin@org1.uniledger.com/tls ./tls
  docker exec cli ./scripts/step1org.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to create config tx"
    exit 1
  fi
}

# We use the cryptogen tool to generate the cryptographic material
# (x509 certs) for the new org.  After we run the tool, the certs will
# be parked in the BYFN folder titled ``crypto-config``.

# Generates Org certs using cryptogen tool
function generateCerts (){
  which cryptogen
  if [ "$?" -ne 0 ]; then
    echo "cryptogen tool not found. exiting"
    exit 1
  fi
  echo
  echo "###############################################################"
  echo "##### Generate Org certificates using cryptogen tool #########"
  echo "###############################################################"

   set -x
   cryptogen generate --config=./org-crypto.yaml
   res=$?
   set +x
   if [ $res -ne 0 ]; then
     echo "Failed to generate certificates..."
     exit 1
   fi
  echo
}

# Generate channel configuration transaction
function generateChannelArtifacts() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo "configtxgen tool not found. exiting"
    exit 1
  fi
  echo "##########################################################"
  echo "#########  Generating Org config material ###############"
  echo "##########################################################"
   export FABRIC_CFG_PATH=$PWD
   set -x
   configtxgen -printOrg Org${ORGCODE}MSP > ../channel-artifacts/org.json
   res=$?
   set +x
   if [ $res -ne 0 ]; then
     echo "Failed to generate Org config material..."
     exit 1
   fi
  cp -r crypto-config/ordererOrganizations crypto-config/
  echo
}



# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform
OS_ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
CLI_TIMEOUT=10
#default for delay
CLI_DELAY=3
# channel name defaults to "mychannel"
CHANNEL_NAME="mychannel"
# org code defaults to "4"
ORGCODE="4"
# use this as the default docker-compose yaml definition
COMPOSE_FILE=docker-compose-cli.yaml
#
#
# use golang as the default language for chaincode
LANGUAGE=golang
# default image tag
IMAGETAG="latest"

# Parse commandline args
if [ "$1" = "-m" ];then	# supports old usage, muscle memory is powerful!
    shift
fi
MODE=$1;shift
# Determine whether starting, stopping, restarting or generating for announce
if [ "$MODE" == "up" ]; then
  EXPMODE="Starting"
elif [ "$MODE" == "down" ]; then
  EXPMODE="Stopping"
elif [ "$MODE" == "restart" ]; then
  EXPMODE="Restarting"
elif [ "$MODE" == "generate" ]; then
  EXPMODE="Generating certs and genesis block for"
else
  printHelp
  exit 1
fi
while getopts "h?c:t:d:f:s:l:i:v" opt; do
  case "$opt" in
    h|\?)
      printHelp
      exit 0
    ;;
    c)  CHANNEL_NAME=$OPTARG
    ;;
    o)  ORGCODE=$OPTARG
    ;;
    t)  CLI_TIMEOUT=$OPTARG
    ;;
    d)  CLI_DELAY=$OPTARG
    ;;
    l)  LANGUAGE=$OPTARG
    ;;
    i)  IMAGETAG=$OPTARG
    ;;
    v)  VERBOSE=true
    ;;
  esac
done

# Announce what was requested
echo
echo "${EXPMODE} with channel '${CHANNEL_NAME}' and CLI timeout of '${CLI_TIMEOUT}' seconds and CLI delay of '${CLI_DELAY}' seconds and using database COUCHDB"
# ask for confirmation to proceed
askProceed

#Create the network using docker compose
if [ "${MODE}" == "up" ]; then
  networkUp
elif [ "${MODE}" == "down" ]; then ## Clear the network
  networkDown
elif [ "${MODE}" == "generate" ]; then ## Generate Artifacts
  #generateCerts
  #generateChannelArtifacts
  #createConfigTx elif [ "${MODE}" == "restart" ]; then ## Restart the network
  networkDown
  networkUp
else
  printHelp
  exit 1
fi
