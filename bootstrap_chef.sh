#!/bin/bash

# Parameters:
# $1 is the vagrant install mode or user name to SSH as (see "Usage:" below)
# $2 is the IP address of the bootstrap node
# $3 is the optional knife recipe name, default "Test-Laptop"

if [[ $OSTYPE == msys || $OSTYPE == cygwin ]]; then
  # try to fix permission mismatch between windows and real unix
  RSYNCEXTRA="--perms --chmod=a=rwx,Da+x"
fi

set -e
BCPC_DIR="chef-bcpc"
IP=$1
CHEF_ENVIRONMENT=$2
echo "Chef environment: ${CHEF_ENVIRONMENT}"

DIR=`dirname $0`
pushd $DIR

# protect against rsyncing to the wrong bootstrap node
if [[ ! -f "environments/${CHEF_ENVIRONMENT}.json" ]]; then
    echo "Error: environment file ${CHEF_ENVIRONMENT}.json not found"
    exit
fi

echo "Building bins"
cd $BCPC_DIR
sudo ./build_bins.sh
echo "Setting up chef server"
sudo ./setup_chef_server.sh ${CHEF_ENVIRONMENT}"
echo "Setting up chef cookbooks"
cd $BCPC_DIR && ./setup_chef_cookbooks.sh ${IP} "" ${CHEF_ENVIRONMENT}
set -x
echo "Setting up chef environment, roles, and uploading cookbooks"
sudo knife environment from file environments/${CHEF_ENVIRONMENT}.json -u admin -k /etc/chef-server/admin.pem
cd $BCPC_DIR && sudo knife role from file roles/*.json -u admin -k /etc/chef-server/admin.pem; r=\$? && sudo knife role from file roles/*.rb -u admin -k /etc/chef-server/admin.pem; r=\$((r & \$? )) && [[ \$r -lt 1 ]]
sudo knife cookbook upload -a -o cookbooks -u admin -k /etc/chef-server/admin.pem

echo "Enrolling local bootstrap node into chef"
./setup_chef_bootstrap_node.sh ${IP} ${CHEF_ENVIRONMENT}

popd
