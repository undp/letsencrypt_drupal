#!/usr/bin/env bash

# Azure DNS Hook for dehydrated dns-01 challenge
# This script manages TXT records in Azure DNS using REST API
#
# Required environment variables:
# - AZURE_SUBSCRIPTION_ID: Azure Subscription ID
# - AZURE_TENANT_ID: Azure Active Directory Tenant ID
# - AZURE_CLIENT_ID: Service Principal Client ID (App ID)
# - AZURE_CLIENT_SECRET: Service Principal Client Secret
# - AZURE_RESOURCE_GROUP: Resource Group containing the DNS Zone
# - AZURE_DNS_ZONE: DNS Zone name (e.g., example.com)

# Functions.sh adds some useful functions and propagates lots of variables.
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "${CURRENT_DIR}"/../functions.sh "$PROJECT" "$ENVIRONMENT"

# Azure REST API version
API_VERSION="2018-05-01"

# Function to get Azure access token
get_azure_token() {
    local token_endpoint="https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token"
    local response
    
    if ! response=$(curl -s -X POST "$token_endpoint" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${AZURE_CLIENT_ID}" \
        -d "client_secret=${AZURE_CLIENT_SECRET}" \
        -d "scope=https://management.azure.com/.default" \
        -d "grant_type=client_credentials"); then
        logline "Error: Failed to get Azure access token"
        return 1
    fi
    
    # Extract access token from JSON response
    echo "$response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4
}

# Function to extract subdomain from full domain
# For _acme-challenge.example.com with zone example.com, returns _acme-challenge
# For _acme-challenge.sub.example.com with zone example.com, returns _acme-challenge.sub
get_record_name() {
    local full_domain="$1"
    local zone="$2"
    
    # Remove the zone from the end of the domain
    local record_name="${full_domain%."${zone}"}"
    
    # If the domain equals the zone, we're at the root
    if [ "$full_domain" = "$zone" ]; then
        record_name="@"
    fi
    
    echo "$record_name"
}

deploy_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
    
    # Avoid unused variable warning - TOKEN_FILENAME is provided by dehydrated but not used in DNS challenge
    _="${TOKEN_FILENAME}"
    
    logline "Deploying DNS challenge for ${DOMAIN}"
    
    # Validate required environment variables
    if [ -z "$AZURE_SUBSCRIPTION_ID" ] || [ -z "$AZURE_TENANT_ID" ] || \
       [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_CLIENT_SECRET" ] || \
       [ -z "$AZURE_RESOURCE_GROUP" ] || [ -z "$AZURE_DNS_ZONE" ]; then
        logline "Error: Missing required Azure environment variables"
        logline "Required: AZURE_SUBSCRIPTION_ID, AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_RESOURCE_GROUP, AZURE_DNS_ZONE"
        exit 1
    fi
    
    # Get access token
    local access_token
    access_token=$(get_azure_token)
    if [ -z "$access_token" ]; then
        logline "Error: Failed to obtain Azure access token"
        exit 1
    fi
    
    # Construct the record name
    local record_name="_acme-challenge"
    if [ "$DOMAIN" != "$AZURE_DNS_ZONE" ]; then
        local subdomain
        subdomain=$(get_record_name "$DOMAIN" "$AZURE_DNS_ZONE")
        record_name="_acme-challenge.${subdomain}"
    fi
    
    # Azure REST API endpoint for DNS record sets
    local api_url="https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.Network/dnsZones/${AZURE_DNS_ZONE}/TXT/${record_name}?api-version=${API_VERSION}"
    
    # Create TXT record JSON payload
    local json_payload
    json_payload=$(cat <<EOF
{
  "properties": {
    "TTL": 60,
    "TXTRecords": [
      {
        "value": ["${TOKEN_VALUE}"]
      }
    ]
  }
}
EOF
)
    
    # Create or update TXT record
    local response
    if ! response=$(curl -s -X PUT "$api_url" \
        -H "Authorization: Bearer ${access_token}" \
        -H "Content-Type: application/json" \
        -d "$json_payload"); then
        logline "Error: Failed to create TXT record for ${DOMAIN}"
        logline "Response: ${response}"
        exit 1
    fi
    
    logline "Successfully created TXT record ${record_name} for ${DOMAIN}"
    logline "Waiting for DNS propagation (60 seconds)..."
    sleep 60
}

clean_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
    
    # Avoid unused variable warnings - these are provided by dehydrated but not used here
    _="${TOKEN_FILENAME}"
    _="${TOKEN_VALUE}"
    
    logline "Cleaning DNS challenge for ${DOMAIN}"
    
    # Get access token
    local access_token
    access_token=$(get_azure_token)
    if [ -z "$access_token" ]; then
        logline "Warning: Failed to obtain Azure access token for cleanup"
        return
    fi
    
    # Construct the record name
    local record_name="_acme-challenge"
    if [ "$DOMAIN" != "$AZURE_DNS_ZONE" ]; then
        local subdomain
        subdomain=$(get_record_name "$DOMAIN" "$AZURE_DNS_ZONE")
        record_name="_acme-challenge.${subdomain}"
    fi
    
    # Azure REST API endpoint for DNS record sets
    local api_url="https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.Network/dnsZones/${AZURE_DNS_ZONE}/TXT/${record_name}?api-version=${API_VERSION}"
    
    # Delete TXT record
    local response
    if response=$(curl -s -X DELETE "$api_url" \
        -H "Authorization: Bearer ${access_token}"); then
        logline "Successfully deleted TXT record ${record_name} for ${DOMAIN}"
    else
        logline "Warning: Failed to delete TXT record for ${DOMAIN}"
        logline "Response: ${response}"
    fi
}

deploy_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"
    
    # Avoid unused variable warning - CERTFILE is provided by dehydrated but not used here
    _="${CERTFILE}"
    
    slackpost "${PROJECT_ROOT}" "good" "SSL bot ${DRUSH_ALIAS}" "Starting deployment of new certificate for ${DOMAIN} (dns-01 challenge)."
    
    # Should deployment be attempted?
    if [ -z ${CERT_DEPLOY_ENVIRONMENT_UUID+x} ]; then
        # No deploy. Just notify Slack and ask for manual deploy.
        slackpost "${PROJECT_ROOT}" "warning" "SSL bot ${DRUSH_ALIAS}" "*New certificate for ${DOMAIN} was generated.* This instance of undp/letsencrypt_drupal *is not set up to deploy certificate* automatically. The certificate needs to be uploaded to Acquia manually*.\n\nSSH to \`drush ${DRUSH_ALIAS} ssh\` to read files.\nLogin to Acquia and open target environment. Open SSL tab on the left side. Click Install SSL certificate.\n\nText fields:\nSSL certificate: \`cat ${FULLCHAINFILE}\`\nSSL private key: \`cat ${KEYFILE}\`\nCA intermediate certificates: \`cat ${CHAINFILE}\`"
    else
        # Run certificate deployment.
        local cert_deploy_result
        if cert_deploy_result=$(php "$CURRENT_DIR"/../acquia_cloud_cert_deployment/cert_deploy.php "${CERT_DEPLOY_ENVIRONMENT_UUID}" "${KEYFILE}" "${FULLCHAINFILE}" "${CHAINFILE}" "${TIMESTAMP}" --activate --label-prefix "letsencrypt_drupal" 2>&1); then
            # Send successful result to slack.
            slackpost "${PROJECT_ROOT}" "good" "SSL bot ${DRUSH_ALIAS}" "SSL certificate deployment successful. \`\`\`${cert_deploy_result}\`\`\`"
        else
            # Send failure notification to slack.
            slackpost "${PROJECT_ROOT}" "danger" "SSL bot ${DRUSH_ALIAS}" "*SSL certificate deployment failure.* Manual review/fix required! \`\`\`${cert_deploy_result}\`\`\`\n\nNew certificate for ${DOMAIN} *was generated and needs to be uploaded to Acquia manually*.\n\nSSH to \`drush ${DRUSH_ALIAS} ssh\` to read files.\nLogin to Acquia and open target environment. Open SSL tab on the left side. Click Install SSL certificate.\n\nText fields:\nSSL certificate: \`cat ${FULLCHAINFILE}\`\nSSL private key: \`cat ${KEYFILE}\`\nCA intermediate certificates: \`cat ${CHAINFILE}\`"
        fi
        # Output for logging.
        echo "${cert_deploy_result}"
    fi
}

unchanged_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"
    
    # Avoid unused variable warnings - these are provided by dehydrated but not all are used here
    _="${KEYFILE}"
    _="${CERTFILE}"
    _="${FULLCHAINFILE}"
    _="${CHAINFILE}"
    
    slackpost "${PROJECT_ROOT}" "good" "SSL bot ${DRUSH_ALIAS}" "Certificate for ${DOMAIN} is still valid and therefore wasn't reissued. All good."
}

invalid_challenge() {
    local DOMAIN="${1}" RESPONSE="${2}"
    
    slackpost "${PROJECT_ROOT}" "danger" "SSL bot ${DRUSH_ALIAS}" "Invalid_challenge: DNS challenge response has failed for ${DOMAIN} with ${RESPONSE}. Manual fix required!"
}

request_failure() {
    local STATUSCODE="${1}" REASON="${2}" REQTYPE="${3}"
    
    # Avoid unused variable warning - REQTYPE is provided by dehydrated but not used here
    _="${REQTYPE}"
    
    slackpost "${PROJECT_ROOT}" "danger" "SSL bot ${DRUSH_ALIAS}" "Request_failure: HTTP request has failed with status code: ${STATUSCODE} and reason: ${REASON}. Manual fix required!"
}

startup_hook() {
    slackpost "${PROJECT_ROOT}" "good" "SSL bot ${DRUSH_ALIAS}" "SSL certificate check is starting (dns-01 challenge)..."
}

exit_hook() {
    slackpost "${PROJECT_ROOT}" "good" "SSL bot ${DRUSH_ALIAS}" "SSL certificate check finished."
}

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|deploy_cert|unchanged_cert|invalid_challenge|request_failure|startup_hook|exit_hook)$ ]]; then
    "$HANDLER" "$@"
fi
