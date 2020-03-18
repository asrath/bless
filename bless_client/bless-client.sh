#!/bin/bash


set -o errexit
set -o nounset
set -o pipefail

DEBUG=${DEBUG:-""}
if [ ! -z $DEBUG ]; then
  set -o xtrace
fi

TMP_OUTPUT_FILE="/tmp/lambda_invoke_output.json"

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

main() {
    local region="$1"
    local function_name="$2"
    local remote_usernames="$3"
    local key="$4"
    local signed_key="$5"

    aws lambda invoke \
    --invocation-type RequestResponse \
    --function-name "$function_name" \
    --region eu-west-1 \
    --payload "{\"bastion_user\": \"$USER\", \"remote_usernames\": \"$remote_usernames\", \"public_key_to_sign\": \"$(cat ${key})\"}" \
    "$TMP_OUTPUT_FILE" > /dev/null

    cat "$TMP_OUTPUT_FILE" | jq -r '.certificate' > "$signed_key"
    rm -f "$TMP_OUTPUT_FILE"

    echo "Signed SSH key written to $signed_key"
}

main $@
exitCode=$?

set +x

exit $exitCode