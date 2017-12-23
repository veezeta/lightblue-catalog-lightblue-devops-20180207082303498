#!/bin/bash

if [ -z "$suffix" ]
then
  if [ -z "$1" ]
  then 
    exit 99
  else
    suffix=$1
  fi
fi

docker run --net=host  \
   --name lightblue-mysql \
   -e MYSQL_ROOT_PASSWORD="Pass4Admin123" \
   -e MYSQL_USER="dbuser" \
   -e MYSQL_PASSWORD="Pass4dbUs3R" \
   -e MYSQL_DATABASE="inventorydb" \
   ibmcloudacademy/lightblue-mysql &

sleep 20

docker exec lightblue-mysql bash ./load-data.sh

bx service create SecureGateway essentials lightblue-gateway

orgN=`bx target | grep Org | awk '{print $2}'`
spcN=`bx target | grep Space | awk '{print $2}'`
orgId=`bx cf org $orgN --guid | tail -1`
spcId=`bx cf space $spcN --guid | tail -1`
token=`bx iam oauth-tokens | grep UAA | awk '{print $4}'`

sgauth="Authorization: Bearer $token"
sgendp="https://sgmanager.ng.bluemix.net/v1/sgconfig?org_id=$orgId&space_id=$spcId"

intgw=`curl -k -X POST -H "Content-Type: application/json" -H "$sgauth" -d '{"desc":"integrationgw","enf_tok_sec":false}' $sgendp`

gwId=`echo $intgw | grep _id |  grep -Po '(?<={_id:)[^,]*'`
jwt=`echo $intgw | grep jwt |  grep -Po '(?<=jwt:)[^,]*'`

sggwep="https://sgmanager.ng.bluemix.net/v1/sgconfig/$gwId/destinations"
sgauth="Authorization: Bearer $jwt"

mysql=`curl -k -X POST -H "Content-Type: application/json" -H "$sgauth" -d '{"desc":"mysql","ip":"localhost","port":3306,"protocol":"TCP"}' $sggwep`
hostname=`echo $mysql | grep hostname | grep -Po '(?<=\"hostname\":\")[^"]*'`
port=`echo $mysql | grep port | grep -Po '(?<=\"port\":)[^,]*' | grep -v null`

docker run --net=host --name=sgclient -v ~/lightblue-catalog/acl:/root/acl ibmcom/secure-gateway-client -F /root/acl/acl.list $gwId &

sleep 20

// edit config
sed -i 's/cap-sg-prd-5.integration.ibmcloud.com:17645/$hostname:$port/' src/main/resources/application.yml 
./gradlew build -x test

bx app push lightblue-catalog-$suffix -n lightblue-catalog-$suffix

exit
