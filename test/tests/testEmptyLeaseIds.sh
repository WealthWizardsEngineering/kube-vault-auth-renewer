#!/usr/bin/env bash

printf "\n************************\n"
printf "Running test: Test that vault renewer runs without any lease ids\n"

################################################

# set up inputs for this test
export VARIABLES_FILE=$(mktemp -d)/variables
export RENEW_INTERVAL=-1

echo "" | VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault policy write my-policy -
TEST_VAULT_TOKEN=$(VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault token create -policy=my-policy -period=1m -field=token)

echo "export VAULT_TOKEN=${TEST_VAULT_TOKEN}" > ${VARIABLES_FILE}
echo "export LEASE_IDS=" >> ${VARIABLES_FILE}

/usr/src/renew-token.sh  2>&1 >&1 | sed 's/^/>> /'
RESULT="${PIPESTATUS[0]}"
[ "${RESULT}" -gt "0" ] && printf "ERROR: Script returned a non-zero exit code\n"

################################################

# clean up
VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault policy delete my-policy
VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault token revoke ${TEST_VAULT_TOKEN}

cleanEnv

[[ "${RESULT}" -eq 0 ]] && printf "Test passed\n"
return ${RESULT}
