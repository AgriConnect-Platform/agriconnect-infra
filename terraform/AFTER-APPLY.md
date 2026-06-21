# After `terraform apply` — Deployment Steps

Everything is automated through two scripts. SSH in, run the script, done.

---

## Step 0 — Save your Terraform outputs

Run this on your **local machine** from inside `terraform/`:

```bash
terraform output
```

You need these four values for the steps below:

```
alb_dns_name        → your-alb-xxx.ap-south-1.elb.amazonaws.com
bastion_public_ip   → x.x.x.x
backend_private_ip  → 10.0.x.x
frontend_public_ip  → x.x.x.x
```

---

## Step 1 — Backend (one script does everything)

SSH into the backend **via the bastion**:

```bash
ssh -i ~/.ssh/webserver-key-pair.pem \
    -J ubuntu@<BASTION_IP> \
    ubuntu@<BACKEND_IP>
```

Run the install script **as ubuntu (no sudo)**:

```bash
cd /home/ubuntu/AgriConnect
bash scripts/backend-install.sh
```

The script will ask you to enter 4 values. Type these exactly:

```
AWS Region          →  ap-south-1
SNS_TOPIC_ARN       →  arn:aws:sns:ap-south-1:978594443309:AgriConnect-WeatherAlerts
EVENTS_TOPIC_ARN    →  arn:aws:sns:ap-south-1:978594443309:AgriConnect-Events
NOTIFICATIONS_QUEUE_URL  →  https://sqs.ap-south-1.amazonaws.com/978594443309/AgriConnect-Notifications-Queue
```

The script automatically:
- Installs Node.js 20 + PM2
- `npm install` for all 5 services
- Runs database migration
- Runs database seed
- Starts all 5 PM2 services with the correct env vars
- Configures PM2 to auto-start on reboot

When done you'll see `pm2 status` with all 5 services `online`.

---

## Step 2 — Frontend (one script does everything)

Open a **new terminal** and SSH into the frontend directly:

```bash
ssh -i ~/.ssh/webserver-key-pair.pem ubuntu@<FRONTEND_IP>
```

Run the install script **as ubuntu (no sudo)**:

```bash
cd /home/ubuntu/AgriConnect
bash scripts/frontend-install.sh
```

The script automatically:
- Installs Node.js 20 + Nginx
- `npm install` for the frontend
- Builds the React app (no ALB URL needed — uses relative `/api/*` paths)
- Deploys the build to `/var/www/agriconnect`
- Configures and starts Nginx on port 80

---

## Step 3 — Open the app

```
http://<ALB_DNS>
```

---

## Step 4 — Test weather alerts (optional)

Manually trigger the Lambda to verify the full pipeline:

```bash
aws lambda invoke \
  --function-name weather-alert-processor \
  --region ap-south-1 \
  /tmp/out.json && cat /tmp/out.json
```

Then check notification-service logs on the backend:

```bash
pm2 logs agriconnect-notif --lines 30
```

You should see `[SQS Worker] Processing event: WEATHER_ALERT`.

---

## Updating after a code push

**Backend:**
```bash
# SSH into backend
cd /home/ubuntu/AgriConnect
bash scripts/backend-update.sh
```

**Frontend:**
```bash
# SSH into frontend
cd /home/ubuntu/AgriConnect
bash scripts/frontend-update.sh
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `git clone` failed — folder missing | `git clone https://github.com/Asadkhanrtx/AgriConnect.git /home/ubuntu/AgriConnect && sudo chown -R ubuntu:ubuntu /home/ubuntu/AgriConnect` |
| `EACCES permission denied` on npm install | You ran script with `sudo` — fix: `sudo chown -R ubuntu:ubuntu /home/ubuntu/AgriConnect` then re-run script as ubuntu |
| Migration fails `SequelizeConnectionError` | RDS still starting — wait 2 min and rerun script |
| PM2 shows `user = root` | Script was run as root — re-run as ubuntu user (no sudo) |
| ALB returns `502` | PM2 service crashed — `pm2 logs <name> --lines 30` |
| Frontend blank page | Run `pm2 status` on backend; ensure all 5 services are `online` |
| S3 image upload `PermanentRedirect` | `AWS_REGION` missing — `AWS_REGION=ap-south-1 pm2 restart agriconnect-media --update-env` |
| Weather alert emails not arriving | Check SMTP secret in Secrets Manager; `pm2 logs agriconnect-notif` |
