#!/bin/bash -e

# Expected to be run in the root of the Chef Git repository (e.g. chef-bcpc)

set -x

if [[ -f ./proxy_setup.sh ]]; then
  . ./proxy_setup.sh
fi

BOOTSTRAP_IP="${1-localhost}"
USER="${2-root}"
ENVIRONMENT="${3-Test-Laptop}"

# load binary_server_url and binary_server_host (usually the bootstrap)
load_binary_server_info "$ENVIRONMENT"

# make sure we do not have a previous .chef directory in place to allow re-runs
if [[ -f .chef/knife.rb ]]; then
  sudo knife node delete `hostname -f` -y -k /etc/chef-server/admin.pem -u admin || true
  sudo knife client delete `hostname -f` -y -k /etc/chef-server/admin.pem -u admin || true
  mv .chef/ ".chef_found_$(date +"%m-%d-%Y %H:%M:%S")"
fi

mkdir .chef
cat << EOF > .chef/knife.rb
require 'rubygems'
require 'ohai'
o = Ohai::System.new
o.all_plugins
 
log_level                :info
node_name                o[:fqdn]
client_key               "$(pwd)/.chef/#{o[:fqdn]}.pem"
validation_client_name   'chef-validator'
validation_key           '/etc/chef-server/chef-validator.pem'
chef_server_url          'https://${BOOTSTRAP_IP}'
syntax_check_cache_path  '$(pwd)/.chef/syntax_check_cache'
cookbook_path '$(pwd)/cookbooks'
 
ENV['GIT_SSL_NO_VERIFY'] = 'true'
File.umask(0007)
EOF
cd cookbooks

# allow versions on cookbooks via "cookbook version"
for cookbook in "apt 2.4.0" python build-essential cron "chef-client 4.2.4" chef-vault ntp yum logrotate yum-epel sysctl chef_handler 7-zip windows ark sudo ulimit pam ohai "poise 1.0.12" java maven; do
  if [[ ! -d ${cookbook% *} ]]; then
     # unless the proxy was defined this knife config will be the same as the one generated above
    knife cookbook site download $cookbook --config ../.chef/knife.rb
    tar zxf ${cookbook% *}*.tar.gz
    rm ${cookbook% *}*.tar.gz
  fi
done
[[ -d dpkg_autostart ]] || git clone https://github.com/hw-cookbooks/dpkg_autostart.git
if [[ ! -d kafka ]]; then
  git clone https://github.com/mthssdrbrg/kafka-cookbook.git kafka
fi
[[ -d jmxtrans ]] || git clone https://github.com/jmxtrans/jmxtrans-cookbook.git jmxtrans
[[ -d cobblerd ]] || git clone https://github.com/cbaenziger/cobbler-cookbook.git cobblerd -b cobbler_profile
