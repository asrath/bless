#!/bin/bash


set -o errexit
set -o nounset
set -o pipefail

DEBUG=${DEBUG:-""}
if [ ! -z $DEBUG ]; then
  set -o xtrace
fi

TMP_OUTPUT_FILE="/tmp/lambda_invoke_output.json"
SSH_KNOWN_HOSTS="$HOME/.ssh/known_hosts"

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

request_signed_key() {
    local region="$1"
    local function_name="$2"
    local email="$3"
    local remote_usernames="$4"
    local key_path="$5"
    local key=$(cat "$key_path")
    local payload=$(generate_request_payload "$email" "$remote_usernames" "$key")



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
    local email="$1"
    local remote_usernames="$2"
    local key="$3"
    echo "{\"bastion_user\": \"$email\", \"remote_usernames\": \"$remote_usernames\", \"public_key_to_sign\": \"$key\"}"
}

process_lambda_response() {
    local pub_key_path="$1"
    local client_ca
    local error
    local exit_code=0

    error=$(cat "$TMP_OUTPUT_FILE" | jq -r '.errorMessage')
    if [ "$error" == "null" ]; then
        write_signed_cert "$pub_key_path"
        write_ca_to_known_hosts
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

    echo "Signed SSH key written to $signed_key_path"
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

main() {
    # check requirements
    check_reqs

    if [ $# -lt 5 ]; then
        echo "Usage $0 <region> <lambda_name> <email> <remote_username> <public_key_path>"
        return 1
    fi

    local region="$1"
    local function_name="$2"
    local email="$3"
    local remote_usernames="$4"
    local key_path="$5"


    if [ ! -f "$key_path" ]; then
         >&2 echo "Public key $key_path not found"
        return 1
    fi

    request_signed_key "$region" "$function_name" "$email" "$remote_usernames" "$key_path"
    process_lambda_response "$key_path"

    return $?
}

main $@
exit_code=$?

set +x

exit $exit_code