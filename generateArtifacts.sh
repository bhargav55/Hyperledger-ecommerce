#!/bin/sh
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#
export FABRIC_ROOT=$PWD
export FABRIC_CFG_PATH=$PWD
CHANNEL_NAME=mychannel
CONSENSUS_TYPE=solo

# remove previous crypto material and config transactions
rm -fr ./artifacts/channel/crypto-config/*
rm -r ./artifacts/channel/*
rm -rf ./artifacts/crypto-config

# generate crypto material
echo
echo "##########################################################"
echo "##### Generate certificates using cryptogen tool #########"
echo "##########################################################"
CRYPTOGEN=$FABRIC_ROOT/bin/cryptogen
$CRYPTOGEN generate --config=./crypto-config.yaml
if [ "$?" -ne 0 ]; then
  echo "Failed to generate crypto material..."
  exit 1
fi

rm -f artifacts/docker-compose.yaml
cp -f docker-compose-template.yaml artifacts/docker-compose.yaml

CURRENT_DIR=$PWD

cd crypto-config/peerOrganizations/buyer.sample.com/ca/
PRIV_KEY=$(ls *_sk)
echo $PRIV_KEY
cd $CURRENT_DIR
sed -i "s/BUYER_CA_KEY/${PRIV_KEY}/g" artifacts/docker-compose.yaml
cd crypto-config/peerOrganizations/seller.sample.com/ca/
PRIV_KEY=$(ls *_sk)
echo $PRIV_KEY
cd $CURRENT_DIR
sed -i "s/SELLER_CA_KEY/${PRIV_KEY}/g" artifacts/docker-compose.yaml

rm -f artifacts/network-config.yaml
cp -f network-config-template.yaml artifacts/network-config.yaml

cd crypto-config/peerOrganizations/buyer.sample.com/users/Admin@buyer.sample.com/msp/keystore/
ADMIN_KEY=$(ls *_sk)
cd $CURRENT_DIR
sed -i "s/BUYER_ADMIN_KEY/${ADMIN_KEY}/g" artifacts/network-config.yaml

cd crypto-config/peerOrganizations/seller.sample.com/users/Admin@seller.sample.com/msp/keystore/
ADMIN_KEY=$(ls *_sk)
cd $CURRENT_DIR
sed -i "s/SELLER_ADMIN_KEY/${ADMIN_KEY}/g" artifacts/network-config.yaml


echo "##########################################################"
echo "#########  Generating Channel Artifacts ##############"
echo "##########################################################"

CONFIGTXGEN=$FABRIC_ROOT/bin/configtxgen

# generate genesis block for orderer
echo "CONSENSUS_TYPE="$CONSENSUS_TYPE

# generate genesis block for orderer
#solo
#$CONFIGTXGEN -profile TwoOrgsOrdererGenesis -channelID sys-channel -outputBlock ./artifacts/channel/genesis.block

#raft
$CONFIGTXGEN -profile TwoOrgsOrdererGenesis -channelID sys-channel -outputBlock ./artifacts/channel/genesis.block
if [ "$?" -ne 0 ]; then
  echo "Failed to generate orderer genesis block..."
  exit 1
fi

# if [ $CONSENSUS_TYPE == solo ]; then
#     $CONFIGTXGEN -profile TwoOrgsOrdererGenesis -channelID sys-channel -outputBlock ./artifacts/channel/genesis.block
#   elif [ $CONSENSUS_TYPE == kafka ]; then
#     $CONFIGTXGEN -profile SampleDevModeKafka -channelID sys-channel -outputBlock ./artifacts/channel/genesis.block
#   elif [ $CONSENSUS_TYPE == etcdraft ]; then
#     $CONFIGTXGEN -profile SampleMultiNodeEtcdRaft -channelID sys-channel -outputBlock ./artifacts/channel/genesis.block
#   else
#     echo "unrecognized CONSENSUS_TYPE='$CONSENSUS_TYPE'. exiting"
#     exit 1
# fi

# generate channel configuration transaction
$CONFIGTXGEN -profile TwoOrgsChannel -outputCreateChannelTx ./artifacts/channel/mychannel.tx -channelID $CHANNEL_NAME
if [ "$?" -ne 0 ]; then
  echo "Failed to generate channel configuration transaction..."
  exit 1
fi

# generate anchor peer transaction
$CONFIGTXGEN -profile TwoOrgsChannel -outputAnchorPeersUpdate ./artifacts/channel/buyerAnchors.tx -channelID $CHANNEL_NAME -asOrg buyer
if [ "$?" -ne 0 ]; then
  echo "Failed to generate anchor peer update for Org1..."
  exit 1
fi

# generate anchor peer transaction
$CONFIGTXGEN -profile TwoOrgsChannel -outputAnchorPeersUpdate ./artifacts/channel/sellerAnchors.tx -channelID $CHANNEL_NAME -asOrg seller
if [ "$?" -ne 0 ]; then
  echo "Failed to generate anchor peer update for Org2..."
  exit 1
fi

#Copy the certificates to the correct location and then delete the copy
cp -r crypto-config/ artifacts/channel/
rm -r crypto-config
