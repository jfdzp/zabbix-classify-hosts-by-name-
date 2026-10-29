#!/bin/bash
#
# Auto-classify Zabbix hosts into host groups based on their host name.
#
# Two kinds of grouping are applied to every host:
#   - role group  : derived from a substring of the name (e.g. *DCV* -> Domain
#                   Controllers, *VTP* -> Virtualization hosts)
#   - site group  : derived from the leading site code of the name
# Groups are created on demand if they do not exist yet.
#
# Replace the SITES map and credentials with your own. The naming substrings
# in the classification block match a specific host-naming scheme - adapt them.

set -euo pipefail

ZABBIX_URL="https://localhost/api_jsonrpc.php"
ZABBIX_HOST_HEADER="zabbix.example.com"
ZABBIX_USER="zabbix-api"
ZABBIX_PASS=$(cat /etc/zabbix/.api_credentials)

echo "Authenticating against the Zabbix API..."
AUTH_TOKEN=$(curl -k -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" \
  -H "Host: $ZABBIX_HOST_HEADER" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"user.login\",\"params\":{\"username\":\"$ZABBIX_USER\",\"password\":\"$ZABBIX_PASS\"},\"id\":1}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result'])")

if [ -z "$AUTH_TOKEN" ]; then
    echo "ERROR: authentication failed."
    exit 1
fi
echo "Authentication successful."

# Site code -> group name (placeholders)
declare -A SITE_GROUPS=(
    ["AA"]="Site A" ["BB"]="Site B" ["CC"]="Site C"
)

get_or_create_group() {
    local GROUP_NAME="$1"
    GROUP_ID=$(curl -k -s -X POST "$ZABBIX_URL" \
      -H "Content-Type: application/json" -H "Host: $ZABBIX_HOST_HEADER" \
      -H "Authorization: Bearer $AUTH_TOKEN" \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"hostgroup.get\",\"params\":{\"filter\":{\"name\":[\"$GROUP_NAME\"]},\"output\":[\"groupid\"]},\"id\":1}" \
      | python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print(r[0]['groupid'] if r else '')")
    if [ -z "$GROUP_ID" ]; then
        GROUP_ID=$(curl -k -s -X POST "$ZABBIX_URL" \
          -H "Content-Type: application/json" -H "Host: $ZABBIX_HOST_HEADER" \
          -H "Authorization: Bearer $AUTH_TOKEN" \
          -d "{\"jsonrpc\":\"2.0\",\"method\":\"hostgroup.create\",\"params\":{\"name\":\"$GROUP_NAME\"},\"id\":1}" \
          | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['groupids'][0])")
        echo "  Created group '$GROUP_NAME' (ID: $GROUP_ID)" >&2
    fi
    echo "$GROUP_ID"
}

add_host_to_group() {
    local HOST_ID="$1" HOST_NAME="$2" GROUP_ID="$3" GROUP_NAME="$4"
    curl -k -s -X POST "$ZABBIX_URL" \
      -H "Content-Type: application/json" -H "Host: $ZABBIX_HOST_HEADER" \
      -H "Authorization: Bearer $AUTH_TOKEN" \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"hostgroup.massadd\",\"params\":{\"groups\":[{\"groupid\":\"$GROUP_ID\"}],\"hosts\":[{\"hostid\":\"$HOST_ID\"}]},\"id\":1}" > /dev/null
    echo "  '$HOST_NAME' added to group '$GROUP_NAME'"
}

echo ""
echo "Ensuring role groups exist..."
GROUP_ID_DB=$(get_or_create_group "Database Servers")
GROUP_ID_AP=$(get_or_create_group "Application Servers")
GROUP_ID_DC=$(get_or_create_group "Domain Controllers")
GROUP_ID_FS=$(get_or_create_group "File Servers")
GROUP_ID_VT=$(get_or_create_group "Virtualization Hosts")

echo ""
echo "Fetching all hosts..."
HOSTS=$(curl -k -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" -H "Host: $ZABBIX_HOST_HEADER" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"host.get\",\"params\":{\"output\":[\"hostid\",\"host\"]},\"id\":1}" \
  | python3 -c "import sys,json
for h in json.load(sys.stdin)['result']:
    print(h['hostid'] + '|' + h['host'])")

echo ""
echo "Classifying hosts..."
while IFS='|' read -r HOST_ID HOST_NAME; do
    HOST_UPPER=$(echo "$HOST_NAME" | tr '[:lower:]' '[:upper:]')

    # Role groups, matched on a naming-scheme substring
    [[ "$HOST_UPPER" == *"DBV"* ]] && add_host_to_group "$HOST_ID" "$HOST_NAME" "$GROUP_ID_DB" "Database Servers"
    [[ "$HOST_UPPER" == *"APV"* ]] && add_host_to_group "$HOST_ID" "$HOST_NAME" "$GROUP_ID_AP" "Application Servers"
    [[ "$HOST_UPPER" == *"DCV"* ]] && add_host_to_group "$HOST_ID" "$HOST_NAME" "$GROUP_ID_DC" "Domain Controllers"
    [[ "$HOST_UPPER" == *"FSV"* ]] && add_host_to_group "$HOST_ID" "$HOST_NAME" "$GROUP_ID_FS" "File Servers"
    [[ "$HOST_UPPER" == *"VTP"* ]] && add_host_to_group "$HOST_ID" "$HOST_NAME" "$GROUP_ID_VT" "Virtualization Hosts"

    # Site group, matched on the leading site code
    for CODE in "${!SITE_GROUPS[@]}"; do
        if [[ "$HOST_UPPER" == ${CODE}* ]]; then
            GRP="${SITE_GROUPS[$CODE]}"
            GID=$(get_or_create_group "$GRP")
            add_host_to_group "$HOST_ID" "$HOST_NAME" "$GID" "$GRP"
        fi
    done
done <<< "$HOSTS"

curl -k -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" -H "Host: $ZABBIX_HOST_HEADER" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"user.logout\",\"params\":[],\"id\":1}" > /dev/null
echo ""
echo "Done. All hosts classified."
