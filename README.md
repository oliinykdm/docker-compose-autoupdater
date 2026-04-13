# Docker Compose Auto Update

<img width="1247" height="106" alt="image" src="https://github.com/user-attachments/assets/39473a15-b630-4971-8f11-ecee386e85f7" />


Automatic daily update of Docker Compose services on Amazon Linux 2023 (I used it on Bastion Host).

The solution runs once per day using a native **systemd timer**. No third-party tools are required.

## Features

- Runs daily at approximately 03:30 with randomized delay (up to 30 minutes)
- Executes as a dedicated non-root user (`docker-updater`)
- Notifications via **AWS SNS** (supports Email, SMS, etc.)
- Detailed logging to `/var/log/docker-compose-update.log`
- Supports multiple Docker Compose projects
- Secure and fully native (no root privileges for the script)

## Requirements

- Amazon Linux 2023
- Docker and Docker Compose installed
- IAM Role with `sns:Publish` permission on the target SNS topic
- User must be in the `docker` group

## Setup

### 1. Create Dedicated User

```bash
sudo useradd -r -s /bin/false docker-updater
sudo usermod -aG docker docker-updater

# Set ownership on your compose directories
sudo chown -R docker-updater:docker-updater /opt/pocket-id
```

### 2. Create Log File

```bash
sudo touch /var/log/docker-compose-update.log
sudo chown docker-updater:docker /var/log/docker-compose-update.log
sudo chmod 664 /var/log/docker-compose-update.log
```

### 3. Copy Update Script

Copy `update-docker-compose.sh` from the root of the repo to `/usr/local/bin/update-docker-compose.sh`

### 4. Apply a correct permissions

```bash
sudo chmod +x /usr/local/bin/update-docker-compose.sh
sudo chown docker-updater:docker /usr/local/bin/update-docker-compose.sh
```

### 5. Systemd Service

```bash
sudo nano /etc/systemd/system/docker-compose-update.service
```

```ini
[Unit]
Description=Docker Compose Auto Update
Requires=docker.service
After=network-online.target docker.service

[Service]
Type=oneshot
User=docker-updater
Group=docker
ExecStart=/usr/local/bin/update-docker-compose.sh

ReadWritePaths=/var/log/docker-compose-update.log /opt
NoNewPrivileges=yes
ProtectSystem=strict
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

### 6. Systemd Timer

```bash
sudo nano /etc/systemd/system/docker-compose-update.timer
```

```ini
[Unit]
Description=Daily Docker Compose Update Timer

[Timer]
OnCalendar=*-*-* 03:30:00
RandomizedDelaySec=30min
Persistent=true

[Install]
WantedBy=timers.target
```

### 7. Enable and Start

```
sudo systemctl daemon-reload
```
```
sudo systemctl enable --now docker-compose-update.timer
```

## Verification

### Check timer status

```
sudo systemctl status docker-compose-update.timer
```
<img width="891" height="111" alt="image" src="https://github.com/user-attachments/assets/272640e8-0b17-4e4c-92cd-351eecc75801" />


### List active timers
```
sudo systemctl list-timers | grep docker
```

### Manual test run
```
sudo -u docker-updater /usr/local/bin/update-docker-compose.sh
```

### View logs
```
tail -n 50 /var/log/docker-compose-update.log
```
```
journalctl -u docker-compose-update.service -e
```

## Useful commands

| Command                                                  | Description                        |
|----------------------------------------------------------|------------------------------------|
| ```sudo systemctl start docker-compose-update.service``` | Run update manually                |
| ```sudo systemctl list-timers --all```                   | Show all timers and next run times |
| ```tail -f /var/log/docker-compose-update.log```         | Follow log in real time            |


Notification Setup
------------------

* Ensure your SNS topic exists and has active subscriptions (Email, SMS, etc.).
* Update `SNS_TOPIC_ARN` in the script with your actual ARN.
* The EC2 instance IAM Role must allow `sns:Publish` action on that topic.
    

Notes
-----

* The script runs as the non-root user docker-updater (member of the docker group).
* You can add as many directories as needed to the `COMPOSE_DIRS` array.
* The timer uses `Persistent=true`, so missed runs will be executed after reboot.

