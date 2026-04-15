#!/bin/bash
# Docker Compose Auto Update Script with AWS SNS notification
# Best practice: uses IAM Role attached to EC2 instance (no credentials needed)

# ========================= CONFIG =========================
COMPOSE_DIRS=("/opt/pocket-id" "/opt/termix" "/opt/ntfy")
LOGFILE="/var/log/docker-compose-update.log"

NTFY_URL="https://ntfy.sh/topic-*"
NTFY_BEARER_TOKEN="tk_xxxx"

# SNS Configuration
SNS_TOPIC_ARN="arn:aws:sns:eu-central-1:123456789012:Topic"
EMAIL_SUBJECT="Docker Compose Update Report - $(hostname)"

# ========================================================

echo "=== Docker Compose Update started at $(date) on $(hostname) by $(whoami) ===" | tee -a "$LOGFILE"

UPDATED=false
for DIR in "${COMPOSE_DIRS[@]}"; do
  if [ ! -d "$DIR" ]; then
    echo "❌ Directory $DIR does not exist" | tee -a "$LOGFILE"
    continue
  fi

  cd "$DIR" || { echo "❌ Cannot cd to $DIR" | tee -a "$LOGFILE"; continue; }

  echo "→ Updating $DIR ..." | tee -a "$LOGFILE"

  if docker compose pull --quiet >> "$LOGFILE" 2>&1 && \
     docker compose up -d --remove-orphans >> "$LOGFILE" 2>&1; then
    echo "✅ $DIR updated successfully" | tee -a "$LOGFILE"
    UPDATED=true
  else
    echo "❌ Failed to update $DIR" | tee -a "$LOGFILE"
  fi
done


# Clean up old images
docker image prune -f >> "$LOGFILE" 2>&1

# ========================= NOTIFICATION =========================
echo "Sending notification via ntfy..." | tee -a "$LOGFILE"

cat > /tmp/docker-update-msg.txt << EOF
Docker Compose Update Report
============================

Hostname: $(hostname)
User: $(whoami)
Time: $(date)
Updated: ${UPDATED}

Containers from directories updates:
EOF

for DIR in "${COMPOSE_DIRS[@]}"; do
  echo "• $DIR" >> /tmp/docker-update-msg.txt
done

echo "" >> /tmp/docker-update-msg.txt
echo "Recent log output:" >> /tmp/docker-update-msg.txt
echo "==============================" >> /tmp/docker-update-msg.txt

tail -n 40 "$LOGFILE" >> /tmp/docker-update-msg.txt

curl -s -X POST "$NTFY_URL" \
  -H "Authorization: Bearer $NTFY_BEARER_TOKEN" \
  -H "Title: Docker Compose Update - $(hostname)" \
  -H "Priority: low" \
  --data-binary @/tmp/docker-update-msg.txt \
  >> "$LOGFILE" 2>&1 || echo "Failed to send to ntfy" | tee -a "$LOGFILE"

rm -f /tmp/docker-update-msg.txt
