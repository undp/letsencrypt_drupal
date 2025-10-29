# Testing Guide for dns-01 Challenge Support

This guide explains how to test the dns-01 challenge support added to letsencrypt_drupal.

## Prerequisites for dns-01 Testing

Before testing dns-01 challenge support, ensure you have:

1. **Azure DNS Zone** configured with your domain
2. **Azure Service Principal** with DNS Zone Contributor permissions
3. **Required environment variables** set:
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_CLIENT_ID`
   - `AZURE_CLIENT_SECRET`
   - `AZURE_RESOURCE_GROUP`
   - `AZURE_DNS_ZONE`

## Testing Default Behavior (http-01)

The default behavior should remain unchanged - using http-01 challenge:

```bash
# This should use http-01 challenge with Drupal hook
./letsencrypt_drupal.sh projectname environment
```

Expected behavior:
- Uses `hooks/letsencrypt_drupal_hooks.sh`
- Challenge type: `http-01`
- Publishes challenges via Drupal module

## Testing dns-01 Challenge

To test dns-01 challenge with Azure DNS:

```bash
# This should use dns-01 challenge with Azure DNS hook
./letsencrypt_drupal.sh projectname environment dns-01
```

Expected behavior:
- Uses `hooks/azure_dns_hook.sh`
- Challenge type: `dns-01`
- Creates TXT records in Azure DNS
- Waits 60 seconds for DNS propagation
- Cleans up TXT records after validation

## Manual Verification Steps

### 1. Check Log Output

Look for these log messages:

```
Using challenge type: dns-01
Using Azure DNS hook for dns-01 challenge
```

or for http-01:

```
Using challenge type: http-01
Using Drupal hook for http-01 challenge
```

### 2. Verify Hook Script Selection

Check that the correct hook is being used:

```bash
# For dns-01, should show azure_dns_hook.sh
grep 'HOOK=' /tmp/letsencrypt_drupal/baseconfig
```

### 3. Test Azure API Authentication

Create a simple test script to verify Azure credentials work:

```bash
#!/usr/bin/env bash

# Source your config file with Azure credentials
source /path/to/config_project.env.sh

# Test getting an access token
TOKEN_ENDPOINT="https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token"

RESPONSE=$(curl -s -X POST "$TOKEN_ENDPOINT" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${AZURE_CLIENT_ID}" \
    -d "client_secret=${AZURE_CLIENT_SECRET}" \
    -d "scope=https://management.azure.com/.default" \
    -d "grant_type=client_credentials")

if echo "$RESPONSE" | grep -q "access_token"; then
    echo "✓ Azure authentication successful"
else
    echo "✗ Azure authentication failed"
    echo "$RESPONSE"
fi
```

### 4. Verify DNS Record Creation

During dns-01 challenge, check that TXT records are created:

```bash
# Check for _acme-challenge TXT records
dig +short _acme-challenge.yourdomain.com TXT

# Or using Azure CLI
az network dns record-set txt list --resource-group YOUR_RG --zone-name yourdomain.com
```

## Troubleshooting

### Issue: "Failed to get Azure access token"

**Solution:** Verify your Azure credentials are correct and the Service Principal has the necessary permissions.

### Issue: "Failed to create TXT record"

**Solution:** 
- Verify the Service Principal has DNS Zone Contributor role
- Check that the resource group and zone name are correct
- Ensure the Azure API version is supported

### Issue: DNS propagation timeout

**Solution:** 
- Wait longer for DNS propagation (may take more than 60 seconds in some cases)
- Verify your DNS zone is properly configured
- Check that nameservers are responding

## Dry Run Testing

To test without actually requesting certificates from Let's Encrypt:

1. Use the Let's Encrypt staging environment in your dehydrated config:
   ```bash
   CA="https://acme-staging-v02.api.letsencrypt.org/directory"
   ```

2. Test with a test domain or subdomain that won't impact production

## Success Criteria

A successful test should:

1. ✓ Accept the challenge type parameter correctly
2. ✓ Select the appropriate hook script
3. ✓ Create TXT records in Azure DNS (for dns-01)
4. ✓ Successfully validate the domain
5. ✓ Clean up TXT records after validation
6. ✓ Generate valid SSL certificates
7. ✓ Post results to Slack/Teams (if configured)

## Syntax Validation

Before running tests, validate script syntax:

```bash
# Check main script
bash -n letsencrypt_drupal.sh

# Check Azure DNS hook
bash -n hooks/azure_dns_hook.sh

# Run shellcheck for code quality
shellcheck -x letsencrypt_drupal.sh
shellcheck -x hooks/azure_dns_hook.sh
```

## Additional Notes

- The default behavior (http-01) should work exactly as before
- The dns-01 challenge requires no Drupal module but needs Azure DNS access
- Both challenge types can coexist - select the appropriate one per execution
- All existing http-01 functionality is preserved
