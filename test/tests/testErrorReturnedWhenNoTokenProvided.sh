#!/usr/bin/env bash

printf "\n************************\n"
printf "Running test: Test that the an error response is returned when no token or SA have been provided\n"

################################################

# set up inputs for this test
export VARIABLES_FILE=$(mktemp -d)/variables

/usr/src/renew-token.sh  2>&1 >&1 | sed 's/^/>> /'
if [ "${PIPESTATUS}" -gt "0" ]; then
    RESULT=0
else
    printf "ERROR: Expected the script to return a error code, but it returned a success code\n"
    RESULT=1
fi

################################################

# clean up

cleanEnv

[[ "${RESULT}" -eq 0 ]] && printf "Test passed\n"
return ${RESULT}
