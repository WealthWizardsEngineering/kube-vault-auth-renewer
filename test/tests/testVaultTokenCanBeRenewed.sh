#!/usr/bin/env bash

printf "\n************************\n"
printf "Running test: Test that the vault token is renewed when the remaining ttl is low\n"

################################################

# set up inputs for this test
export VARIABLES_FILE=$(mktemp -d)/variables
export RENEW_INTERVAL=180
export RUN_ONCE=true

echo "" | VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault policy write my-policy - > /dev/null
TEST_VAULT_TOKEN=$(VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault token create -policy=my-policy -period=1m -field=token)

echo "export VAULT_TOKEN=${TEST_VAULT_TOKEN}" > ${VARIABLES_FILE}

/usr/src/renew-token.sh  2>&1 >&1 | sed 's/^/>> /'
RESULT="${PIPESTATUS[0]}"
[ "${RESULT}" -gt "0" ] && printf "ERROR: Script returned a non-zero exit code\n"

################################################

# assert output
last_renewal=$(curl -sS --request PUT \
    --header "X-Vault-Token: ${SETUP_VAULT_TOKEN}" \
    ${VAULT_ADDR}/v1/auth/token/lookup \
    -H "Content-Type: application/json" \
    -d '{"token":"'"${TEST_VAULT_TOKEN}"'"}' | \
    jq -r 'if .errors then . else .data.last_renewal end')

assertNotEquals "token should have a renewal date set if it's been renewed" "null" "${last_renewal}" || RESULT=1

################################################

# clean up
VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault token revoke ${TEST_VAULT_TOKEN} > /dev/null

cleanEnv

[[ "${RESULT}" -eq 0 ]] && printf "Test passed\n"
return ${RESULT}
