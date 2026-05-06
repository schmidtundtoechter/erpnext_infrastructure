#!/usr/bin/env bash

set -u

REMOTE_HOST="vepro"
PORTS=(8080 9090)
CONTAINERS=(
	"erp_erpnext_frontend_container"
	"erptest_erpnext_frontend_container"
)
REFERENCE_HOST="sut.netcup"
REFERENCE_CONTAINER="erpnext-demo_erpnext_frontend_container"

print_header() {
	local title="$1"
	printf "\n============================================================\n"
	printf "%s\n" "$title"
	printf "============================================================\n"
}

print_result() {
	local label="$1"
	local value="$2"
	printf "%-50s %s\n" "$label" "$value"
}

print_header "1) Listening Ports On Host (${REMOTE_HOST})"
for port in "${PORTS[@]}"; do
	if ssh "$REMOTE_HOST" "ss -tln | grep -q ':${port} '"; then
		print_result "Port ${port} listening on host" "[OK]"
	else
		print_result "Port ${port} listening on host" "[FAIL]"
	fi
done

print_header "2) HTTP Check From Host (${REMOTE_HOST} -> localhost:<port>)"
for port in "${PORTS[@]}"; do
	code=$(ssh "$REMOTE_HOST" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${port}" 2>/dev/null || true)
	if [[ "$code" =~ ^[0-9]{3}$ && "$code" != "000" ]]; then
		print_result "curl localhost:${port}" "HTTP ${code}"
	else
		print_result "curl localhost:${port}" "[FAIL] no response"
	fi
done

print_header "3) HTTP Check Inside Frontend Container (ssh -> docker exec -> curl)"
for container in "${CONTAINERS[@]}"; do
	code=$(ssh "$REMOTE_HOST" "docker exec ${container} curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080" 2>/dev/null || true)
	if [[ "$code" =~ ^[0-9]{3}$ && "$code" != "000" ]]; then
		print_result "docker exec ${container} curl 127.0.0.1:8080" "HTTP ${code}"
	else
		print_result "docker exec ${container} curl 127.0.0.1:8080" "[FAIL] container/curl unreachable"
	fi
done

print_header "4) Reference Test (ssh -> docker exec on ${REFERENCE_HOST})"
code=$(ssh "$REFERENCE_HOST" "docker exec ${REFERENCE_CONTAINER} curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080" 2>/dev/null || true)
if [[ "$code" =~ ^[0-9]{3}$ && "$code" != "000" ]]; then
	print_result "docker exec ${REFERENCE_CONTAINER} curl 127.0.0.1:8080" "HTTP ${code}"
else
	print_result "docker exec ${REFERENCE_CONTAINER} curl 127.0.0.1:8080" "[FAIL] reference container/curl unreachable"
fi

printf "\nDone.\n"