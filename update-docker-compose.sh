#!/bin/bash
# Docker Compose Auto Update Script with AWS SNS notification
# Best practice: uses IAM Role attached to EC2 instance (no credentials needed)

# ========================= CONFIG =========================
COMPOSE_DIRS=("/opt/pocket-id" "/opt/termix" ) # Your docker compose dirs here
LOGFILE="/var/log/docker-compose-update.log"

# SNS Configuration
SNS_TOPIC_ARN="arn:aws:sns:us-west-1:123456788012:SNS-Topic-Name"
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
echo "Sending notification via SNS..." | tee -a "$LOGFILE"

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

# Last 40 lines from logs
tail -n 40 "$LOGFILE" >> /tmp/docker-update-msg.txt

# Send as file thgough SNS (works better)
aws sns publish \
  --topic-arn "$SNS_TOPIC_ARN" \
  --subject "✅ Docker Compose Update - $(hostname)" \
  --message file:///tmp/docker-update-msg.txt \
  >> "$LOGFILE" 2>&1 || echo "❌ Failed to publish to SNS" | tee -a "$LOGFILE"

# Removing temp file
rm -f /tmp/docker-update-msg.txt
