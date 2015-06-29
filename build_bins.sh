#!/bin/bash 

set -e
set -x

# Define the version of Zabbix server and zabbixapi gem to be downloaded
# Refer https://github.com/bloomberg/chef-bcpc/issues/343
ZABBIX_VERSION=2.2.2   

# Define the appropriate version of each binary to grab/build
VER_KIBANA=d1495fbf6e9c20c707ecd4a77444e1d486a1e7d6
VER_DIAMOND=d64cc5cbae8bee93ef444e6fa41b4456f89c6e12
VER_ESPLUGIN=c3635657f4bb5eca0d50afa8545ceb5da8ca223a

# The proxy and $CURL will be needed later
if [[ -f ./proxy_setup.sh ]]; then
  . ./proxy_setup.sh
fi

if [[ -z "$CURL" ]]; then
  echo "CURL is not defined"
  exit
fi

DIR=`dirname $0`

mkdir -p $DIR/bins
pushd $DIR/bins/

# create directory for Python bins
mkdir -p python

# create directory for dpkg's
APT_REPO_VERSION=0.5.0
APT_REPO="dists/${APT_REPO_VERSION}/"
APT_REPO_BINS="${APT_REPO}/main/binary-amd64/"
mkdir -p $APT_REPO_BINS

# Get up to date
apt-get -y update

# Install tools needed for packaging
apt-get -y install git rubygems make pbuilder python-mock python-configobj python-support cdbs python-all-dev python-stdeb libmysqlclient-dev libldap2-dev ruby-dev gcc patch rake ruby1.9.3 ruby1.9.1-dev python-pip python-setuptools dpkg-dev apt-utils haveged libtool autoconf unzip rsync autogen
if [[ -z `gem list --local fpm | grep fpm | cut -f1 -d" "` ]]; then
  gem install fpm --no-ri --no-rdoc
fi

# Download jmxtrans zip file
if ! [[ -f jmxtrans-20120525-210643-4e956b1144.zip ]]; then
  $CURL -O -L -k https://github.com/downloads/jmxtrans/jmxtrans/jmxtrans-20120525-210643-4e956b1144.zip
fi
FILES="jmxtrans-20120525-210643-4e956b1144.zip $FILES"

# Fetch MySQL connector
if ! [[ -f mysql-connector-java-5.1.34.tar.gz ]]; then
  $CURL -O -L http://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.34.tar.gz
fi
FILES="mysql-connector-java-5.1.34.tar.gz $FILES"

# Fetch Kafka Tar
for version in 0.8.1 0.8.1.1; do
  mkdir -p kafka/${version}/
  if ! [[ -f kafka/${version}/kafka_2.9.2-${version}.tgz ]]; then
    pushd kafka/${version}/
    $CURL -O -L https://archive.apache.org/dist/kafka/${version}/kafka_2.9.2-${version}.tgz
    popd
  fi
  FILES="kafka_2.9.2-${version}.tgz $FILES"
done

# Fetch Java Tar
if ! [[ -f jdk-7u51-linux-x64.tar.gz ]]; then
  $CURL -O -L -C - -b "oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jdk/7u51-b13/jdk-7u51-linux-x64.tar.gz   
fi
FILES="jdk-7u51-linux-x64.tar.gz $FILES"

if ! [[ -f UnlimitedJCEPolicyJDK7.zip ]]; then
  $CURL -O -L -C - -b "oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jce/7/UnlimitedJCEPolicyJDK7.zip
fi
FILES="UnlimitedJCEPolicyJDK7.zip $FILES"

if ! [[ -f jce_policy-8.zip ]]; then
  $CURL -O -L -C - -b "oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jce/8/jce_policy-8.zip
fi
FILES="jce_policy-8.zip $FILES"

# Pull all the gems required for the cluster 
for i in patron wmi-lite simple-graphite; do
  if ! [[ -f gems/${i}.gem ]]; then
    gem fetch ${i}
    ln -s ${i}-*.gem ${i}.gem || true
  fi
  FILES="${i}*.gem $FILES"
done

# Get the Rubygem for zookeeper
if ! [[ -f gems/zookeeper.gem ]]; then
  gem fetch zookeeper -v 1.4.7
  ln -s zookeeper-*.gem zookeeper.gem || true
fi
FILES="zookeeper*.gem $FILES"

# Fetch the cirros image for testing
if ! [[ -f cirros-0.3.0-x86_64-disk.img ]]; then
  $CURL -O -L https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-disk.img
fi
FILES="cirros-0.3.0-x86_64-disk.img $FILES"

# Fetch pyrabbit
if ! [[ -f python/pyrabbit-1.0.1.tar.gz ]]; then
  while ! $(file python/pyrabbit-1.0.1.tar.gz | grep -q 'gzip compressed data'); do
    (cd python && $CURL -O -L http://pypi.python.org/packages/source/p/pyrabbit/pyrabbit-1.0.1.tar.gz)
  done
fi
FILES="pyrabbit-1.0.1.tar.gz $FILES"

# Download Python requests-aws for Zabbix monitoring
if ! [[ -f python-requests-aws_0.1.5_all.deb ]]; then
  fpm -s python -t deb -v 0.1.5 requests-aws
fi
FILES="python-requests-aws_0.1.5_all.deb $FILES"

# Build the zabbix packages
if [ ! -f zabbix-agent.tar.gz ] || [ ! -f zabbix-server.tar.gz ]; then
    $CURL -L -O http://sourceforge.net/projects/zabbix/files/ZABBIX%20Latest%20Stable/${ZABBIX_VERSION}/zabbix-${ZABBIX_VERSION}.tar.gz
    tar zxf zabbix-${ZABBIX_VERSION}.tar.gz
    rm -rf /tmp/zabbix-install && mkdir -p /tmp/zabbix-install
    cd zabbix-${ZABBIX_VERSION}
    ./configure --prefix=/tmp/zabbix-install --enable-agent --with-ldap
    make install
    tar zcf zabbix-agent.tar.gz -C /tmp/zabbix-install .
    rm -rf /tmp/zabbix-install && mkdir -p /tmp/zabbix-install
    ./configure --prefix=/tmp/zabbix-install --enable-server --with-mysql --with-ldap
    make install
    cp -a frontends/php /tmp/zabbix-install/share/zabbix/
    cp database/mysql/* /tmp/zabbix-install/share/zabbix/
    tar zcf zabbix-server.tar.gz -C /tmp/zabbix-install .
    rm -rf /tmp/zabbix-install
    cd ..
    cp zabbix-${ZABBIX_VERSION}/zabbix-agent.tar.gz .
    cp zabbix-${ZABBIX_VERSION}/zabbix-server.tar.gz .
    rm -rf zabbix-${ZABBIX_VERSION} zabbix-${ZABBIX_VERSION}.tar.gz
fi
FILES="zabbix-agent.tar.gz zabbix-server.tar.gz $FILES"

# Gather the Chef packages and provide a dpkg repo
opscode_urls="https://opscode-omnibus-packages.s3.amazonaws.com/debian/6/12.04/x86_64/chef_11.18.12-1_amd64.deb
https://opscode-omnibus-packages.s3.amazonaws.com/debian/6/x86_64/chef-server_11.1.7-1_amd64.deb"
for url in $opscode_urls; do
  if ! [[ -f $(basename $url) ]]; then
    $CURL -L -O $url
  fi
done

###################
# generate apt-repo
dpkg-scanpackages . > ${APT_REPO_BINS}/Packages
gzip -c ${APT_REPO_BINS}/Packages > ${APT_REPO_BINS}/Packages.gz
tempfile=$(mktemp)
rm -f ${APT_REPO}/Release
rm -f ${APT_REPO}/Release.gpg
echo -e "Version: ${APT_REPO_VERSION}\nSuite: ${APT_REPO_VERSION}\nComponent: main\nArchitecture: amd64" > ${APT_REPO_BINS}/Release
apt-ftparchive -o APT::FTPArchive::Release::Version=${APT_REPO_VERSION} -o APT::FTPArchive::Release::Suite=${APT_REPO_VERSION} -o APT::FTPArchive::Release::Architectures=amd64 -o APT::FTPArchive::Release::Components=main release dists/${APT_REPO_VERSION} > $tempfile
mv $tempfile ${APT_REPO}/Release

# generate a key and sign repo
if ! [[ -f ${HOME}/apt_key.sec && -f apt_key.pub ]]; then
  rm -rf ${HOME}/apt_key.sec apt_key.pub
  gpg --batch --gen-key << EOF
    Key-Type: DSA
    Key-Length: 4096
    Key-Usage: sign
    Name-Real: Local BCPC Repo
    Name-Comment: For dpkg repo signing
    Expire-Date: 0
    %pubring apt_key.pub
    %secring ${HOME}/apt_key.sec
    %commit
EOF
  chmod 700 ${HOME}/apt_key.sec
fi
gpg --no-tty -abs --keyring ./apt_key.pub --secret-keyring ${HOME}/apt_key.sec -o ${APT_REPO}/Release.gpg ${APT_REPO}/Release

# generate ASCII armored GPG key
gpg --import ./apt_key.pub
gpg -a --export $(gpg --list-public-keys --with-colons | grep 'Local BCPC Repo' | cut -f 5 -d ':') > apt_key.asc
# ensure everything is readable in the bins directory
chmod -R 755 .

####################
# generate Pypi repo

# Wheel installs require setuptools >= 0.8 for dist-info support.
# can then follow http://askubuntu.com/questions/399446
# but can't upgrade setuptools first as:
# "/usr/bin/pip install: error: no such option: --no-use-wheel"
if ! hash dir2pi; then
  /usr/bin/pip install pip2pi || /bin/true
  /usr/local/bin/pip install setuptools --no-use-wheel --upgrade
  /usr/local/bin/pip install pip2pi
fi

dir2pi python

#########################
# generate rubygems repos

# need the builder gem to generate a gem index
if [[ -z `gem list --local builder | grep builder | cut -f1 -d" "` ]]; then
  gem install builder --no-ri --no-rdoc
fi

# place all gems into the server normally
[ ! -d gems ] && mkdir gems
[ "$(echo *.gem)" != '*.gem' ] && mv *.gem gems
gem generate_index --legacy

popd
