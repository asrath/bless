#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

DEBUG=${DEBUG:-""}
if [ ! -z $DEBUG ]; then
  set -o xtrace
fi

USERDATA_TPL_FILENAME="user-data.tpl.sh"
CLIENT_SCRIPT="bless_client_host_inside_instance.py"
TPL_PLACEHOLDER="#client-script#"
USERDATA_FILENAME="user-data.sh"

compile() {
    local line
    cat "$(pwd)/$USERDATA_TPL_FILENAME" | while IFS= read -r line || [ -n "$line" ]; do
        if [ "$line" == "$TPL_PLACEHOLDER" ]; then
            echo "$client_script_content" >> "$(pwd)/$USERDATA_FILENAME"
        else
            echo "$line" >> "$(pwd)/$USERDATA_FILENAME"
        fi
    done
}

main () {
    if [ ! -f "$(pwd)/$USERDATA_TPL_FILENAME" ]; then
        >&2 echo "ERROR: $(pwd)/$USERDATA_TPL_FILENAME not found"
        return 1
    fi

    if [ ! -f "$(pwd)/$CLIENT_SCRIPT" ]; then
        >&2 echo "ERROR: $(pwd)/$CLIENT_SCRIPT not found"
        return 1
    fi

    rm -f "$(pwd)/$USERDATA_FILENAME"

    client_script_content=$(cat "$CLIENT_SCRIPT")

    compile

    chmod +x "$(pwd)/$USERDATA_FILENAME"

    return 0
}

main $@
exitCode=$?

set +x

exit $exitCode