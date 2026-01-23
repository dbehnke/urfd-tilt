#!/bin/bash
echo "=== Container Status ==="
docker ps -a | grep dashboard239

echo -e "\n=== Recent Errors Only ==="
docker logs dashboard239 2>&1 | grep -vE "INSERT|UPDATE|SELECT|rows:" | grep -iE "error|fatal|panic|fail|warn" | tail -20

echo -e "\n=== Startup Messages ==="
docker logs dashboard239 2>&1 | grep -E "Starting|Config loaded|Listen|voice" | tail -10

echo -e "\n=== Config Being Used ==="
docker exec dashboard239 cat /etc/dashboard/config.yaml 2>&1 | grep -A10 voice

echo -e "\n=== Is Dashboard Responding? ==="
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:8081/ 2>&1 || echo "Failed to connect"
