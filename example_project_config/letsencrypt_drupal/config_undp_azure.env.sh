#!/usr/bin/env bash

# Example Azure DNS configuration for dns-01 challenge
# Copy this file and adjust values for your Azure environment

# Slack/Teams endpoint and target channel (optional).
# Get it here: https://my.slack.com/services/new/incoming-webhook/
SLACK_WEBHOOK_URL='https://hooks.slack.com/services/XXXXXXXXX/XXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXX'
SLACK_CHANNEL='CHANNEL-NAME'

TEAMS_WEBHOOK_URL=''

# UUID of target environment for cert deploy.
# Easiest to get from URL in Acquia Cloud UI. See https://cloudapi-docs.acquia.com/#/Environments/getEnvironment
# (Second uuid in URL when looking at specific environment.)
CERT_DEPLOY_ENVIRONMENT_UUID="XXXXXX-XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"

# Azure DNS Configuration for dns-01 challenge
# These should be stored securely and sourced from a secrets file
# For Acquia Cloud, store in /mnt/files/PROJECT.ENV/secrets.settings.php or similar

# Azure Subscription ID
export AZURE_SUBSCRIPTION_ID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"

# Azure Active Directory Tenant ID
export AZURE_TENANT_ID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"

# Service Principal Client ID (Application ID)
export AZURE_CLIENT_ID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"

# Service Principal Client Secret
export AZURE_CLIENT_SECRET="YOUR-CLIENT-SECRET-HERE"

# Resource Group containing the DNS Zone
export AZURE_RESOURCE_GROUP="your-resource-group-name"

# DNS Zone name (e.g., example.com)
export AZURE_DNS_ZONE="example.com"
