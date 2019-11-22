#!/usr/bin/env bash

printf "\n************************\n"
printf "Running test: Test that the an error response is returned when the max ttl is reached and a lease cannot be renewed for the full period\n"

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
    max_ttl="1m" > /dev/null > /dev/null

lease_id="$(VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault read -field=lease_id database/creds/my-role)"
echo "export LEASE_IDS=${lease_id}" >> ${VARIABLES_FILE}

# Wait so that the lease ttl has decreased a little
sleep 10

/usr/src/renew-token.sh  2>&1 >&1 | sed 's/^/>> /'
if [ "${PIPESTATUS}" -gt "0" ]; then
    RESULT=0
else
    printf "ERROR: Expected the script to return a error code, but it returned a success code\n"
    RESULT=1
fi

################################################

# clean up
VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault secrets disable database > /dev/null
VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault policy delete my-policy > /dev/null
VAULT_TOKEN=${SETUP_VAULT_TOKEN} vault token revoke ${TEST_VAULT_TOKEN} > /dev/null

cleanEnv

[[ "${RESULT}" -eq 0 ]] && printf "Test passed\n"
return ${RESULT}
