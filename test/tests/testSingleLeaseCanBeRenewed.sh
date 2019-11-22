#!/usr/bin/env bash

printf "\n************************\n"
printf "Running test: Test that a single lease is renewed when the remaining ttl is low\n"

################################################

# set up inputs for this test
export VARIABLES_FILE=$(mktemp -d)/variables
export RENEW_INTERVAL=180
export RUN_ONCE=true

echo 'path "*" { policy = "read" }' | VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault policy write my-policy - > /dev/null
TEST_VAULT_TOKEN=$(VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault token create -policy=my-policy -period=1h -field=token)

echo "export VAULT_TOKEN=${TEST_VAULT_TOKEN}" > ${VARIABLES_FILE}

VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault secrets enable database > /dev/null

VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault write database/config/my-mongodb-database \
    plugin_name=mongodb-database-plugin \
    allowed_roles="my-role" \
    connection_url="mongodb://@mongo/admin" > /dev/null

VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault write database/roles/my-role \
    db_name=my-mongodb-database \
    creation_statements='{ "db": "admin", "roles": [{ "role": "readWrite" }, {"role": "read", "db": "foo"}] }' \
    default_ttl="1m" \
    max_ttl="1h" > /dev/null > /dev/null

lease_id="$(VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault read -field=lease_id database/creds/my-role)"
echo "export LEASE_IDS=${lease_id}" >> ${VARIABLES_FILE}

/usr/src/renew-token.sh  2>&1 >&1 | sed 's/^/>> /'
RESULT="${PIPESTATUS[0]}"
[ "${RESULT}" -gt "0" ] && printf "ERROR: Script returned a non-zero exit code\n"

################################################

# assert output
last_renewal=$(curl -sS --request PUT \
    --header "X-Vault-Token: ${SETUP_VAULT_TOKEN}" \
    ${VAULT_ADDR}/v1/sys/leases/lookup \
    -H "Content-Type: application/json" \
    -d '{"lease_id":"'"${lease_id}"'"}' | \
    jq -r 'if .errors then . else .data.last_renewal end')

assertNotEquals "lease should have a renewal date set if it's been renewed" "null" "${last_renewal}" || RESULT=1

################################################

# clean up
VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault secrets disable database > /dev/null
VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault policy delete my-policy > /dev/null
VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault token revoke ${TEST_VAULT_TOKEN} > /dev/null

cleanEnv

[[ "${RESULT}" -eq 0 ]] && printf "Test passed\n"
return ${RESULT}
