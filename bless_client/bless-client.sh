#!/bin/bash

# https://gist.github.com/asrath/7b8ce01bd92d650fe914b83d0dfa3ab4

set -o errexit
set -o nounset
set -o pipefail

if [ ! -z ${TRACE+x} ]; then
  set -o xtrace
fi

TMP_OUTPUT_FILE="/tmp/lambda_invoke_output.json"
SSH_KNOWN_HOSTS="$HOME/.ssh/known_hosts"
INSTALL_CA=${INSTALL_CA:-""}

check_reqs() {
    local missing_reqs=0

    if [ $(command_installed aws) -eq 0 ]; then
        echo $("ERROR: 'aws' missing. Install instructions: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html")
        missing_reqs=1
    fi

    if [ $(command_installed jq) -eq 0 ]; then
        echo $("ERROR: 'jq' missing. Download: https://stedolan.github.io/jq/download/")
        missing_reqs=1
    fi

    if [ $missing_reqs -eq 1 ]; then
        exit 1
    fi
}

command_installed() {
    local executable="$1"

    if [ $SHELL = '/bin/zsh' ] || [ $SHELL = '/usr/bin/zsh' ]; then
        if [ $(which "$executable") = "$executable not found" ]; then
            # not found
            echo 0
        else
            # found
            echo 1
        fi
    else
        # assume bash shell
        if [ $(which "$executable" | wc -l) -eq 0 ]; then
            # not found
            echo 0
        else
            # found
            echo 1
        fi
    fi
}

get_current_iam_user() {
    aws iam get-user | jq -r '.User.UserName'
}

request_signed_key() {
    local region="$1"
    local function_name="$2"
    local iam_user="$3"
    local remote_usernames="$4"
    local key_path="$5"
    local key=$(cat "$key_path")
    local payload=$(generate_request_payload "$iam_user" "$remote_usernames" "$key")

    # support for awscli v1 and v2
    if [ ! -z $(aws --version | grep "aws-cli/1.*" || [[ $? == 1 ]]) ]; then
        aws lambda invoke \
        --invocation-type RequestResponse \
        --function-name "$function_name" \
        --region "$region" \
        --payload "$payload" \
        "$TMP_OUTPUT_FILE" > /dev/null
    else
        aws lambda invoke \
        --cli-binary-format raw-in-base64-out \
        --invocation-type RequestResponse \
        --function-name "$function_name" \
        --region "$region" \
        --payload "$payload" \
        "$TMP_OUTPUT_FILE" > /dev/null
    fi
}

generate_request_payload() {
    local iam_user="$1"
    local remote_usernames="$2"
    local key="$3"
    echo "{\"bastion_user\": \"$iam_user\", \"remote_usernames\": \"$remote_usernames\", \"public_key_to_sign\": \"$key\"}"
}

process_lambda_response() {
    local pub_key_path="$1"
    local install_ca=$2
    local client_ca
    local error
    local exit_code=0

    error=$(cat "$TMP_OUTPUT_FILE" | jq -r '.errorMessage')
    if [ "$error" == "null" ]; then
        write_signed_cert "$pub_key_path"
        [ $install_ca -gt 0 ] && write_ca_to_known_hosts
    else
        exit_code=2
        >&2 echo "An error has occurred in certificate lambda invocation"
        cat "$TMP_OUTPUT_FILE" | jq
    fi
    rm -f "$TMP_OUTPUT_FILE"

    return $exit_code
}

write_signed_cert() {
    local pub_key_path="$1"
    local signed_key_path=$(get_signed_key_path "$pub_key_path")

    cat "$TMP_OUTPUT_FILE" | jq -r '.certificate' > "$signed_key_path"

    echo -e "Signed SSH key written to $signed_key_path\n"
    [ ! -z ${DEBUG+x} ] && ssh-keygen -L -f "$signed_key_path"
}

get_signed_key_path() {
    local key_path="$1"
    local signed_key_path
    local filename
    local extension

    filename=$(basename -- "$key_path")
    extension="${filename##*.}"
    filename="${filename%.*}"

    signed_key_path="$(dirname "$key_path")/${filename}-cert.$extension"

    echo "$signed_key_path"
}

write_ca_to_known_hosts() {
    if [ -z $INSTALL_CA ]; then
      return
    fi

    local ca_pub_key=$(cat "$TMP_OUTPUT_FILE" | jq -r '.ca_pub_key')
    local client_ca=$(cat "$TMP_OUTPUT_FILE" | jq -r '.client_ca[]')
    local known_hosts

    # check if there is CA public key in the response
    if [ "$ca_pub_key" == "null" ]; then
        echo "No CA public key provided. Skip setting CA"
        return
    fi

    # if there is no .ssh dir do nothing
    if [ ! -d $(dirname -- "$SSH_KNOWN_HOSTS") ]; then
        echo "$(dirname -- "$SSH_KNOWN_HOSTS") not found. Skip setting CA"
        return
    fi

    # check if cert authority is already set
    if [ -f "$SSH_KNOWN_HOSTS" ]; then
        echo cat "$SSH_KNOWN_HOSTS" | grep -e "@cert-authority .* $ca_pub_key"
        if [ ! -z $(cat "$SSH_KNOWN_HOSTS" | grep -e "@cert-authority .* $ca_pub_key" || [[ $? == 1 ]]) ]; then
            return
        fi

        # backup known_hosts and empty it
        cp "$SSH_KNOWN_HOSTS" "$SSH_KNOWN_HOSTS.old" && \
        rm -f "$SSH_KNOWN_HOSTS" && \
        touch "$SSH_KNOWN_HOSTS"
    else
        # create empty known_hosts
        touch "$SSH_KNOWN_HOSTS"
    fi

    echo "$client_ca" | while read -r ca; do
        echo "$ca $ca_pub_key" >> "$SSH_KNOWN_HOSTS"
    done

    echo "CA key written to $SSH_KNOWN_HOSTS"
}

usage () {
    echo "usage: $0 [-hc] [--help] [--install-ca] [--region <region>] <lambda_name> <remote_username> <public_key_path>"
    echo " "
    echo "options:"
    echo -e "--help -h \t\t This help"
    echo -e "--install-ca -c \t Install certificate authority in known hosts file"
    echo -e "--region \t\t AWS region where the lambda function is located. Defaults to awscli default region"
}

main() {
    # check requirements
    check_reqs

    # read the options from cli input
    TEMP=$(getopt --options h --longoptions help,install-ca,region: -n $0 -- "$@")
    eval set -- "${TEMP}"

    # default region to awscli default
    local region=$(aws configure get region)
    local install_ca=0

    # extract options and their arguments into variables.
    while true; do
        case "$1" in
            -h | --help)
                usage
                return 0
                ;;
            -c | --install-ca)
                install_ca=1
                ;;
            --region)
                region="$2";
                [ ${region:0:1} == "-" ] && echo "$1 requires a valid value" && return 1
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Unrecognized option: $1"
                return 1
                ;;
        esac
    done

    if [ $# -lt 3 ]; then
        usage
        return 1
    fi

    local function_name="$1"
    local remote_usernames="$2"
    local key_path="$3"
    local iam_user


    if [ ! -f "$key_path" ]; then
         >&2 echo "Public key $key_path not found"
        return 1
    fi

    iam_user=$(get_current_iam_user)
    request_signed_key "$region" "$function_name" "$iam_user" "$remote_usernames" "$key_path"
    process_lambda_response "$key_path" $install_ca

    return $?
}

main $@
exit_code=$?

set +x

exit $exit_code