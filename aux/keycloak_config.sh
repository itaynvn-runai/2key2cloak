#!/bin/bash

# list of vars to check
variables=("CLUSTER_DOMAIN" "OPERATOR" "PROTOCOL" "KEYCLOAK_ADMIN" "KEYCLOAK_ADMIN_PASSWORD" "KEYCLOAK_URL" "REALM_NAME" "USER_FIRST_NAME" "USER_LAST_NAME" "USER_EMAIL" "USER_USERNAME" "INIT_USER_PASSWORD" "CLIENT_ID")
# Check if any var is empty
for var in "${variables[@]}"; do
    if [[ -n "${!var}" ]]; then
        echo "$var = ${!var}"
    else
        echo "$var is empty."
        empty=true
    fi
done

# Check if all vars are populated
if [[ -z $empty ]]; then
    echo "* All variables populated! moving on... *"
else
    echo "* One or more variables are empty :( *"
    exit 1
fi

# Check the value of OPERATOR and perform actions accordingly
if [ "$OPERATOR" = "slim" ]; then
    echo "* using slim operator settings *"
    PROTOCOL="https"
    APP_REDIRECT_URI="$PROTOCOL://app.$CLUSTER_DOMAIN/oauth2/callback"
    KIBANA_REDIRECT_URI="$PROTOCOL://sso-central.$CLUSTER_DOMAIN/oauth2/callback"
    WEB_ORIGINS="$PROTOCOL://app.$CLUSTER_DOMAIN/*"
elif [ "$OPERATOR" = "v4" ]; then
    echo "* using v4 operator settings *"
    APP_REDIRECT_URI="$PROTOCOL://app.$CLUSTER_DOMAIN/oauth2/callback"
    KIBANA_REDIRECT_URI="$PROTOCOL://kibana.$CLUSTER_DOMAIN/oauth2/callback"
    WEB_ORIGINS="$PROTOCOL://app.$CLUSTER_DOMAIN/*"
else
    echo "Invalid operator: $OPERATOR"
    exit 1
fi
echo "* redirect URL's configured *"

# Get new admin access token function
get_access_token() {
  ACCESS_TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$KEYCLOAK_ADMIN" \
    -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
    -d 'grant_type=password' \
    -d 'client_id=admin-cli' | jq -r '.access_token')
  echo $ACCESS_TOKEN
}

# Create a new realm 
NEW_TOKEN=$(get_access_token)
curl -s -X POST "$KEYCLOAK_URL/admin/realms" \
    -H "Authorization: Bearer $NEW_TOKEN" \
    -H "Content-Type: application/json" \
    --data-raw "{
    \"realm\": \"$REALM_NAME\",
    \"enabled\": true}"
echo "* realm created *"

# Create a new user
NEW_TOKEN=$(get_access_token)
curl -s -X POST "$KEYCLOAK_URL/admin/realms/$REALM_NAME/users" \
-H "Authorization: Bearer $NEW_TOKEN" \
-H "Content-Type: application/json" --data-raw "{
    \"firstName\":\"$USER_FIRST_NAME\",
    \"lastName\":\"$USER_LAST_NAME\",
    \"email\":\"$USER_EMAIL\",
    \"username\":\"$USER_USERNAME\",
    \"enabled\":\"true\",
    \"emailVerified\": true,
    \"credentials\": [{\"type\": \"password\", \"value\": \"$INIT_USER_PASSWORD\", \"temporary\": false}]}"
echo "* new init user created *"

# Create an OIDC client
NEW_TOKEN=$(get_access_token)
curl --location --request POST "$KEYCLOAK_URL/admin/realms/$REALM_NAME/clients" \
--header "Authorization: Bearer $NEW_TOKEN" \
--header 'Content-Type: application/json' \
--data-raw "{
    \"clientId\": \"$CLIENT_ID\",
    \"redirectUris\": [\"$APP_REDIRECT_URI\",\"$KIBANA_REDIRECT_URI\"],
    \"webOrigins\": [\"$WEB_ORIGINS\"],
    \"standardFlowEnabled\": true
}"
echo "* OIDC client created *"

# Get OIDC client UUID
NEW_TOKEN=$(get_access_token)
CLIENT_UUID=$(curl --location --request GET "$KEYCLOAK_URL/admin/realms/$REALM_NAME/clients" \
--header "Authorization: Bearer $NEW_TOKEN" \
| jq -r ".[] | select(.clientId==\"$CLIENT_ID\") | .id")
echo "* OIDC client UUID retrieved *"

# Enable authentication and retrieve client secret
NEW_TOKEN=$(get_access_token)
CLIENT_SECRET=$(curl --location --request GET "$KEYCLOAK_URL/admin/realms/$REALM_NAME/clients/$CLIENT_UUID/client-secret" \
--header "Authorization: Bearer $NEW_TOKEN" \
| jq -r ".value")
echo "* auth enabled + client secret retrieved * \n CLIENT_UUID: $CLIENT_UUID \n CLIENT_SECRET: $CLIENT_SECRET"
echo -e "*** post install script finished :) ***\n"
env
