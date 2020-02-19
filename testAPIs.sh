#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

jq --version > /dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "Please Install 'jq' https://stedolan.github.io/jq/ to execute this script"
	echo
	exit 1
fi

starttime=$(date +%s)

# Print the usage message
function printHelp () {
  echo "Usage: "
  echo "  ./testAPIs.sh -l golang|node"
  echo "    -l <language> - chaincode language (defaults to \"golang\")"
}
# Language defaults to "golang"
LANGUAGE="golang"

# Parse commandline args
while getopts "h?l:" opt; do
  case "$opt" in
    h|\?)
      printHelp
      exit 0
    ;;
    l)  LANGUAGE=$OPTARG
    ;;
  esac
done

##set chaincode path
function setChaincodePath(){
	LANGUAGE=`echo "$LANGUAGE" | tr '[:upper:]' '[:lower:]'`
	case "$LANGUAGE" in
		"golang")
		CC_SRC_PATH="github.com/example_cc/go"
		;;
		"node")
		CC_SRC_PATH="$PWD/artifacts/src/github.com/example_cc/node"
		;;
		*) printf "\n ------ Language $LANGUAGE is not supported yet ------\n"$
		exit 1
	esac
}

setChaincodePath

echo "POST request Enroll on buyer  ..."
echo
BUYER_TOKEN=$(curl -s -X POST \
  http://localhost:4000/users \
  -H "content-type: application/x-www-form-urlencoded" \
  -d 'username=Jim&orgName=buyer')
echo $BUYER_TOKEN
BUYER_TOKEN=$(echo $BUYER_TOKEN | jq ".token" | sed "s/\"//g")
echo
echo "buyer token is $BUYER_TOKEN"
echo
echo "POST request Enroll on seller ..."
echo
SELLER_TOKEN=$(curl -s -X POST \
  http://localhost:4000/users \
  -H "content-type: application/x-www-form-urlencoded" \
  -d 'username=Barry&orgName=seller')
echo $SELLER_TOKEN
SELLER_TOKEN=$(echo $SELLER_TOKEN | jq ".token" | sed "s/\"//g")
echo
echo "seller token is $SELLER_TOKEN"
echo
echo
echo "POST request Create channel  ..."
echo
curl -s -X POST \
  http://localhost:4000/channels \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json" \
  -d '{
	"channelName":"mychannel",
	"channelConfigPath":"../artifacts/channel/mychannel.tx"
}'
echo
echo
sleep 5
echo "POST request Join channel on buyer"
echo
curl -s -X POST \
  http://localhost:4000/channels/mychannel/peers \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json" \
  -d '{
	"peers": ["peer0.buyer.sample.com","peer1.buyer.sample.com"]
}'
echo
echo

echo "POST request Join channel on seller"
echo
curl -s -X POST \
  http://localhost:4000/channels/mychannel/peers \
  -H "authorization: Bearer $SELLER_TOKEN" \
  -H "content-type: application/json" \
  -d '{
	"peers": ["peer0.seller.sample.com","peer1.seller.sample.com"]
}'
echo
echo

echo "POST request Update anchor peers on buyer"
echo
curl -s -X POST \
  http://localhost:4000/channels/mychannel/anchorpeers \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json" \
  -d '{
	"configUpdatePath":"../artifacts/channel/buyerAnchors.tx"
}'
echo
echo

echo "POST request Update anchor peers on seller"
echo
curl -s -X POST \
  http://localhost:4000/channels/mychannel/anchorpeers \
  -H "authorization: Bearer $SELLER_TOKEN" \
  -H "content-type: application/json" \
  -d '{
	"configUpdatePath":"../artifacts/channel/sellerAnchors.tx"
}'
echo
echo

echo "POST Install chaincode on buyer"
echo
curl -s -X POST \
  http://localhost:4000/chaincodes \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json" \
  -d "{
	\"peers\": [\"peer0.buyer.sample.com\",\"peer1.buyer.sample.com\"],
	\"chaincodeName\":\"mycc\",
	\"chaincodePath\":\"$CC_SRC_PATH\",
	\"chaincodeType\": \"$LANGUAGE\",
	\"chaincodeVersion\":\"v0\"
}"
echo
echo

echo "POST Install chaincode on seller"
echo
curl -s -X POST \
  http://localhost:4000/chaincodes \
  -H "authorization: Bearer $SELLER_TOKEN" \
  -H "content-type: application/json" \
  -d "{
	\"peers\": [\"peer0.seller.sample.com\",\"peer1.seller.sample.com\"],
	\"chaincodeName\":\"mycc\",
	\"chaincodePath\":\"$CC_SRC_PATH\",
	\"chaincodeType\": \"$LANGUAGE\",
	\"chaincodeVersion\":\"v0\"
}"
echo
echo

echo "POST instantiate chaincode on buyer"
echo
curl -s -X POST \
  http://localhost:4000/channels/mychannel/chaincodes \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json" \
  -d "{
	\"chaincodeName\":\"mycc\",
	\"chaincodeVersion\":\"v0\",
	\"chaincodeType\": \"$LANGUAGE\",
	\"args\":[\"\"]
}"
echo
echo

echo "POST invoke chaincode on peers of buyer and seller"
echo
curl -s -X POST \
  http://localhost:4000/channels/mychannel/chaincodes/mycc \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json" \
  -d "{
	\"peers\": [\"peer0.buyer.sample.com\",\"peer0.seller.sample.com\"],
	\"fcn\":\"invoke\",
  \"operation\":\"createProduct\",
	\"args\": [\"createProduct\",\"Product-Name\", \"Product - Description\",\"100\",\"1000\"]
}"
echo
echo

echo "GET query chaincode on peer1 of buyer"
echo
curl -s -X GET \
  "http://localhost:4000/channels/mychannel/chaincodes/mycc?peer=peer0.buyer.sample.com&fcn=query&args=%5B%22a%22%5D" \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json"
echo
echo

echo "GET query Block by blockNumber"
echo
BLOCK_INFO=$(curl -s -X GET \
  "http://localhost:4000/channels/mychannel/blocks/1?peer=peer0.buyer.sample.com" \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json")
echo $BLOCK_INFO
# Assign previvious block hash to HASH
HASH=$(echo $BLOCK_INFO | jq -r ".header.previous_hash")
echo

echo "GET query Transaction by TransactionID"
echo
curl -s -X GET http://localhost:4000/channels/mychannel/transactions/$TRX_ID?peer=peer0.buyer.sample.com \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json"
echo
echo


echo "GET query Block by Hash - Hash is $HASH"
echo
curl -s -X GET \
  "http://localhost:4000/channels/mychannel/blocks?hash=$HASH&peer=peer0.buyer.sample.com" \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "cache-control: no-cache" \
  -H "content-type: application/json" \
  -H "x-access-token: $BUYER_TOKEN"
echo
echo

echo "GET query ChainInfo"
echo
curl -s -X GET \
  "http://localhost:4000/channels/mychannel?peer=peer0.buyer.sample.com" \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json"
echo
echo

echo "GET query Installed chaincodes"
echo
curl -s -X GET \
  "http://localhost:4000/chaincodes?peer=peer0.buyer.sample.com" \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json"
echo
echo

echo "GET query Instantiated chaincodes"
echo
curl -s -X GET \
  "http://localhost:4000/channels/mychannel/chaincodes?peer=peer0.buyer.sample.com" \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json"
echo
echo

echo "GET query Channels"
echo
curl -s -X GET \
  "http://localhost:4000/channels?peer=peer0.buyer.sample.com" \
  -H "authorization: Bearer $BUYER_TOKEN" \
  -H "content-type: application/json"
echo
echo


echo "Total execution time : $(($(date +%s)-starttime)) secs ..."
