#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

export LAMBDA_NAME="SSHCA"

METADATA_URL='http://169.254.169.254/latest/meta-data'
INSTANCE_IP=$(curl -s "$METADATA_URL/local-ipv4")
AZ=$(curl -s "$METADATA_URL/placement/availability-zone")
REGION=${AZ%[a-z]}
PRIV_HOSTNAME=$(curl -s "$METADATA_URL/hostname")

BLESS_CLIENT="/tmp/bless_client_host.py"
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
HOST_PUB_KEY="/etc/ssh/ssh_host_rsa_key.pub"
HOST_PUB_KEY_CERT="/etc/ssh/ssh_host_rsa_key-cert.pub"
CA_PUB_KEY="/etc/ssh/ssh-ca.pub"
LAMBDA_NAME=${LAMBDA_NAME:-bless}

install_aws_tools() {
    echo "Installing AWS tools..."
    PATH=$PATH:/usr/local/bin

    [ $(which apt-get) ] && apt-get update
    [ ! $(which unzip) ] && [ $(which apt-get) ] && DEBIAN_FRONTEND=noninteractive apt-get -y install unzip
    [ ! $(which pip) ] && [ $(which apt-get) ] && DEBIAN_FRONTEND=noninteractive apt-get -y install python3-pip
    [ ! $(which pip) ] && [ $(which yum) ] && yum install -y python3-pip
    python3 -m pip install --upgrade pip
    #python3 -m pip install awscli --ignore-installed six
    #python3 -m pip install aws-cfn-bootstrap
    python3 -m pip install boto3

    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
}

install_bless_client() {
    cat <<EOF > "$BLESS_CLIENT"
#client-script#
EOF
}

figure_hostnames() {
    local hnames="$INSTANCE_IP,$PRIV_HOSTNAME"

    if [ $(get_http_status_code "$METADATA_URL/public-hostname") -eq 200 ]; then
        hnames="$hnames,$(curl -s "$METADATA_URL/public-hostname")"
    fi

    if [ $(get_http_status_code "$METADATA_URL/public-ipv4") -eq 200 ]; then
        hnames="$hnames,$(curl -s "$METADATA_URL/public-ipv4")"
    fi

    echo "$hnames"
}

get_http_status_code() {
    local url="$1"
    curl -sILk -o /dev/null -m1 -XGET -w "%{http_code}\n" "$url"
}

setup_sshd() {
    echo "TrustedUserCAKeys $CA_PUB_KEY" >> "$SSHD_CONFIG_FILE"
    echo "HostCertificate $HOST_PUB_KEY_CERT" >> "$SSHD_CONFIG_FILE"

    echo "HostCertificate and TrustedUserCAKeys set in $SSHD_CONFIG_FILE"

    [ $(which apt-get) ] && systemctl restart ssh
    [ $(which yum) ] && systemctl restart sshd
}

install_aws_tools
install_bless_client

#curl -s "$METADATA_URL/identity-credentials/ec2/security-credentials/ec2-instance"
hostnames=$(figure_hostnames)

if [ $(get_http_status_code "$METADATA_URL/public-hostname") -eq 200 ]; then
    hostnames="$hostnames,$(curl -s "$METADATA_URL/public-hostname")"
fi

if [ $(get_http_status_code "$METADATA_URL/public-ipv4") -eq 200 ]; then
    hostnames="$hostnames,$(curl -s "$METADATA_URL/public-ipv4")"
fi

python3 "$BLESS_CLIENT" "$REGION" SSHCA "$hostnames" "$HOST_PUB_KEY" "$HOST_PUB_KEY_CERT"

setup_sshd
