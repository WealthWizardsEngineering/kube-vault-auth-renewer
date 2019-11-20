#!/usr/bin/env sh

set -eo pipefail

validateVaultResponse () {
  if echo ${2} | grep "errors"; then
    echo "ERROR: unable to retrieve ${1}: ${2}"
    exit 1
  fi
}

#########################################################################

[[ -z ${VARIABLES_FILE} ]] && VARIABLES_FILE='/env/variables'

#########################################################################

if [ -f ${VARIABLES_FILE} ]; then source ${VARIABLES_FILE}; fi
if [ -z ${RENEW_INTERVAL+x} ]; then RENEW_INTERVAL=21600; else echo "RENEW_INTERVAL is set to '${RENEW_INTERVAL}'"; fi

while true
do
    TOKEN_LOOKUP_RESPONSE=$(curl -sS \
      --header "X-Vault-Token: ${VAULT_TOKEN}" \
      ${VAULT_ADDR}/v1/auth/token/lookup-self | \
      jq -r 'if .errors then . else . end')
    validateVaultResponse 'token lookup' "${TOKEN_LOOKUP_RESPONSE}"

    CREATION_TTL=$(echo ${TOKEN_LOOKUP_RESPONSE} | jq -r '.data.creation_ttl')
    CURRENT_TTL=$(echo ${TOKEN_LOOKUP_RESPONSE} | jq -r '.data.ttl')
    RENEW_INTERVAL_TTL_THRESHOLD=$(expr ${RENEW_INTERVAL} \* 2)
    RENEWAL_TTL_THRESHOLD=$(expr ${CREATION_TTL} / 2)

    # Only renew if the current ttl is below half the original ttl
    # and if there's any risk of it expiring before the next renewal check
    if [ ${CURRENT_TTL} -lt ${RENEWAL_TTL_THRESHOLD} -o ${CURRENT_TTL} -lt ${RENEW_INTERVAL_TTL_THRESHOLD} ]; then
        echo "Renewing token from Vault server: ${VAULT_ADDR}, ttl: ${CURRENT_TTL}"

        TOKEN_RENEW=$(curl -sS --request POST \
          --header "X-Vault-Token: ${VAULT_TOKEN}" \
          ${VAULT_ADDR}/v1/auth/token/renew-self | \
          jq -r 'if .errors then . else .auth.client_token end')
        validateVaultResponse 'renew token' "${TOKEN_RENEW}"

        echo "Token renewed"
    else
        echo "Token not renewed, ttl: ${CURRENT_TTL}"
    fi

    #######################################################################

    # Renew secrets if they we have their lease ids

    lease_ids=$(echo ${LEASE_IDS} | tr "," "\n")

    for lease_id in $lease_ids
    do
        LEASE_LOOKUP_RESPONSE=$(curl -sS --request PUT \
          --header "X-Vault-Token: ${VAULT_TOKEN}" \
          ${VAULT_ADDR}/v1/sys/leases/lookup \
          -H "Content-Type: application/json" \
          -d '{"lease_id":"'"${lease_id}"'"}' | \
          jq -r 'if .errors then . else .data end')
        validateVaultResponse "lease lookup (${lease_id})" "${LEASE_LOOKUP_RESPONSE}"

        RENEW_INTERVAL_TTL_THRESHOLD=$(expr ${RENEW_INTERVAL} \* 2)
        CURRENT_TTL=$(echo ${LEASE_LOOKUP_RESPONSE} | jq -r '.ttl')

        # Only renew if there's any risk of it expiring before the next renewal check
        if [ ${CURRENT_TTL} -lt ${RENEW_INTERVAL_TTL_THRESHOLD} ]; then
            echo "Renewing secret: ${lease_ids}, ttl: ${CURRENT_TTL}"

            SECRET_RENEW=$(curl -sS --request PUT \
              --header "X-Vault-Token: ${VAULT_TOKEN}" \
              ${VAULT_ADDR}/v1/sys/leases/renew \
              -H "Content-Type: application/json" \
              -d '{"lease_id":"'"${lease_id}"'"}' | \
              jq -r 'if .errors then . else . end')
            validateVaultResponse "renew secret ($lease_id)" "${SECRET_RENEW}"

            echo "Secret renewed"
        else
            echo "Secret not renewed, ttl: ${CURRENT_TTL}"
        fi
    done

    if [[ "${RENEW_INTERVAL}" -lt 0 ]]; then
      exit 0
    else
      sleep ${RENEW_INTERVAL}
    fi
done
