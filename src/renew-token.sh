#!/usr/bin/env sh

validateVaultResponse () {
  local action="$1"
  local responsePayload="$2"

  if echo "${responsePayload}" | grep "errors" > /dev/null; then
    local message=$(echo "${responsePayload}" | jq -r '.[] | join (",")')
    echo "ERROR: request returned errors ${action}, error message: ${message}" >&2
    return 1
  elif [[ $(echo "${responsePayload}" | jq -r '.warnings != null') == "true" ]]; then
    local message=$(echo "${responsePayload}" | jq -r '.warnings | join (",")')
    echo "ERROR: request returned warnings ${action}, warning message: ${message}" >&2
    return 1
  else
    return 0
  fi

}

lookupToken () {
  local vault_token=$1

  response="$(VAULT_TOKEN=${vault_token} vault token lookup -format=json 2>&1)"
  if [[ $? -gt 0 ]]; then
    echo "ERROR: unable to retrieve token, error message: ${response}" >&2
    return 1
  else
    if validateVaultResponse "token" "${response}"; then
      echo ${response}
      return 0
    else
      return 1
    fi
  fi
}

#########################################################################

[[ -z ${VARIABLES_FILE} ]] && VARIABLES_FILE='/env/variables'

#########################################################################

if [[ -f ${VARIABLES_FILE} ]]; then source ${VARIABLES_FILE}; fi
if [[ -z ${RENEW_INTERVAL+x} ]]; then RENEW_INTERVAL=21600; else echo "Renewal interval is set to '${RENEW_INTERVAL}'"; fi
[[ -z ${VAULT_TOKEN+x} ]] && echo "ERROR: VAULT_TOKEN is not set" && exit 1

while true
do
    token_lookup_response=$(lookupToken ${VAULT_TOKEN})
    if [[ $? -gt 0 ]]; then
      exit 1
    fi

    CREATION_TTL=$(echo ${token_lookup_response} | jq -r '.data.creation_ttl')
    CURRENT_TTL=$(echo ${token_lookup_response} | jq -r '.data.ttl')
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
        validateVaultResponse 'renew token' "${TOKEN_RENEW}" || exit 1

        echo "Token renewed"
    else
        echo "Token not renewed, ttl: ${CURRENT_TTL}"
    fi

    #######################################################################

    # Renew secrets if we have their lease ids

    lease_ids=$(echo ${LEASE_IDS} | tr "," "\n")

    for lease_id in $lease_ids
    do
        LEASE_LOOKUP_RESPONSE=$(curl -sS --request PUT \
          --header "X-Vault-Token: ${VAULT_TOKEN}" \
          ${VAULT_ADDR}/v1/sys/leases/lookup \
          -H "Content-Type: application/json" \
          -d '{"lease_id":"'"${lease_id}"'"}' | \
          jq -r 'if .errors then . else .data end')

        validateVaultResponse "lease (${lease_id})" "${LEASE_LOOKUP_RESPONSE}" || exit 1

        RENEW_INTERVAL_TTL_THRESHOLD=$(expr ${RENEW_INTERVAL} \* 2)
        CURRENT_TTL=$(echo ${LEASE_LOOKUP_RESPONSE} | jq -r '.ttl')

        # Only renew if there's any risk of it expiring before the next renewal check
        if [ ${CURRENT_TTL} -lt ${RENEW_INTERVAL_TTL_THRESHOLD} ]; then
            echo "Renewing secret: ${lease_ids}, ttl: ${CURRENT_TTL}"

            SECRET_RENEW=$(curl -sS --request PUT \
              --header "X-Vault-Token: ${VAULT_TOKEN}" \
              ${VAULT_ADDR}/v1/sys/leases/renew \
              -H "Content-Type: application/json" \
              -d '{"lease_id":"'"${lease_id}"'"}')
            validateVaultResponse "renew lease ($lease_id)" "${SECRET_RENEW}" || exit 1

            echo "Secret renewed"
        else
            echo "Secret not renewed, ttl: ${CURRENT_TTL}"
        fi
    done

    if [[ "${RUN_ONCE}" = "true" ]]; then
      exit 0
    else
      sleep ${RENEW_INTERVAL}
    fi
done
