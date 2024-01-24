#!/bin/bash

# run this script using the following convention:
#
# bash keycloak_config.sh -d aks-cicd-20375.cicd.cnvrg.me -o v4 -p https
#
# required params:
# --cluster-domain (-d) is the cluster domain of your cnvrg app
# --operator (-o) is the operator version, either "v4" or "slim"
#
# optional params:
# --protocol (-p) is the protocol, by default its http, pass "https" if needed.

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --cluster-domain|-d)
            CLUSTER_DOMAIN="$2"
            shift # past argument
            shift # past value
            ;;
        --operator|-o)
            OPERATOR="$2"
            shift # past argument
            shift # past value
            ;;
        --protocol|-p)
            PROTOCOL="$2"
            shift # past argument
            shift # past value
            ;;
        *) # unknown option
            echo "Unknown option: $key"
            exit 1
            ;;
    esac
done

# list of vars to check
variables=("CLUSTER_DOMAIN" "OPERATOR" "PROTOCOL" "KEYCLOAK_ADMIN" "KEYCLOAK_ADMIN_PASSWORD" "REALM_NAME" "USER_FIRST_NAME" "USER_LAST_NAME" "USER_EMAIL" "USER_USERNAME" "INIT_USER_PASSWORD" "CLIENT_ID")
# Check if any var is empty
for var in "${variables[@]}"; do
    [[ -z "${!var}" ]] && { echo "$var is empty."; empty=true; }
done
[[ -z $empty ]] && echo "All variables populated! moving on..." || echo "One or more variables are empty :(" && exit 1

# set keycloak UI URL
KEYCLOAK_URL="$PROTOCOL://keycloak.$CLUSTER_DOMAIN"

# Check the value of OPERATOR and perform actions accordingly
if [ "$OPERATOR" = "slim" ]; then
    echo "using slim operator settings"
    PROTOCOL="https"
    APP_REDIRECT_URI="$PROTOCOL://app.$CLUSTER_DOMAIN/oauth2/callback"
    KIBANA_REDIRECT_URI="$PROTOCOL://sso-central.$CLUSTER_DOMAIN/oauth2/callback"
    WEB_ORIGINS="$PROTOCOL://app.$CLUSTER_DOMAIN/*"
elif [ "$OPERATOR" = "v4" ]; then
    echo "using v4 operator settings"
    APP_REDIRECT_URI="$PROTOCOL://app.$CLUSTER_DOMAIN/oauth2/callback"
    KIBANA_REDIRECT_URI="$PROTOCOL://kibana.$CLUSTER_DOMAIN/oauth2/callback"
    WEB_ORIGINS="$PROTOCOL://app.$CLUSTER_DOMAIN/*"
else
    echo "Invalid operator: $OPERATOR"
    exit 1
fi

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

# Get OIDC client UUID
NEW_TOKEN=$(get_access_token)
CLIENT_UUID=$(curl --location --request GET "$KEYCLOAK_URL/admin/realms/$REALM_NAME/clients" \
--header "Authorization: Bearer $NEW_TOKEN" \
| jq -r ".[] | select(.clientId==\"$CLIENT_ID\") | .id")

# Enable authentication and retrieve client secret
NEW_TOKEN=$(get_access_token)
CLIENT_SECRET=$(curl --location --request GET "$KEYCLOAK_URL/admin/realms/$REALM_NAME/clients/$CLIENT_UUID/client-secret" \
--header "Authorization: Bearer $NEW_TOKEN" \
| jq -r ".value")

echo "done! creating secrets.."

# create secret with sso section in cnvrgapp:
printf "\n  sso:\n    enabled: true\n    adminUser: $KEYCLOAK_ADMIN\n    provider: oidc\n    emailDomain: [\"*\"]\n    clientId: $CLIENT_ID\n    clientSecret: $CLIENT_SECRET\n    oidcIssuerUrl: $KEYCLOAK_URL/realms/$REALM_NAME\n" | kubectl -n $KEYCLOAK_NAMESPACE create secret generic keycloak-cnvrgapp-config --from-file=cnvrgapp_sso_config.yaml=/dev/stdin
# create secret with kubectl patch command:
printf "kubectl -n cnvrg patch cnvrgapp cnvrg-app --type=json -p='[{\"op\": \"replace\", \"path\": \"/spec/sso\", \"value\": {\"adminUser\": \"$KEYCLOAK_ADMIN\", \"clientId\": \"$CLIENT_ID\", \"clientSecret\": \"$CLIENT_SECRET\", \"emailDomain\": [\"*\", \"mycorp.net\"], \"enabled\": true, \"oidcIssuerUrl\": \"$KEYCLOAK_URL/realms/$REALM_NAME\", \"provider\": \"oidc\"}}]'" | kubectl -n $KEYCLOAK_NAMESPACE create secret generic keycloak-cnvrgapp-kubectl --from-file=cnvrgapp_sso_kubectl.sh=/dev/stdin