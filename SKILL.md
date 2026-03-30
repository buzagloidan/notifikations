---
name: notifikations
description: >
  Send push notifications to your iPhone or Mac using Notifikations webhook URLs.
  Use this skill when a user wants to get notified on their phone from any script,
  automation, deployment, CI/CD pipeline, smart home, or third-party service.
  Covers all payload fields, scheduling, named webhooks, action buttons, and
  ready-to-use code for curl, Python, JavaScript, GitHub Actions, Home Assistant,
  Claude Code hooks, n8n, Zapier, Apple Shortcuts, and more.
---

## What is Notifikations?

Notifikations gives you a personal webhook URL. Hit it from anywhere — a script, a CI job, a cron task, a smart home — and a push notification lands on your iPhone or Mac instantly. No account. No login. The URL is the credential.

Get the app at **notifikations.com** and copy your webhook URL from the main screen.

---

## Sending a notification

The base URL is:
```
https://api.notifikations.com/api/v1/YOUR_SECRET
```

**Simplest possible call — plain text body:**
```bash
curl -X POST https://api.notifikations.com/api/v1/YOUR_SECRET \
  -d 'Deploy finished ✅'
```

**GET request (useful when only URLs are supported):**
```
https://api.notifikations.com/api/v1/YOUR_SECRET?message=Hello&title=Alert
```

**JSON with full control:**
```bash
curl -X POST https://api.notifikations.com/api/v1/YOUR_SECRET \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Build done",
    "message": "All tests passed",
    "sound": "brrr"
  }'
```

---

## All payload fields

| Field | Type | Notes |
|-------|------|-------|
| `message` | string | **Required.** Notification body. |
| `title` | string | Bold heading above the message. |
| `subtitle` | string | Secondary line below title. |
| `sound` | string | `"default"`, `"none"`, or a custom sound name (e.g. `"brrr"`). |
| `thread_id` | string | Groups related notifications in Notification Center. |
| `open_url` | string | URL or deep link opened when the user taps. |
| `image_url` | string | Remote image shown in the expanded notification. |
| `interruption-level` | string | `"passive"` (silent), `"active"` (default), `"time-sensitive"` (breaks Focus). |
| `filter-criteria` | string | iOS Focus filter value. |
| `expiration_date` | ISO 8601 | Discard the notification after this time if undelivered. |
| `send_at` | ISO 8601 | Schedule delivery up to 30 days ahead (max 10 pending per URL). |
| `category` | string | Show action buttons: `"YES_NO"`, `"APPROVE_DISMISS"`, `"CONFIRM"`. |
| `callback_url` | string | Your server receives a POST `{"action":"yes"}` when the user taps a button. |

GET requests accept all the same fields as query parameters.

---

## Secrets and targeting

| Secret type | What it does |
|-------------|--------------|
| **Device secret** (`ntf_dev_…`) | Sends to one specific device only. |
| **User secret** (`ntf_usr_…`) | Fan-out — sends to all your registered devices simultaneously. |
| **Named webhook secret** | An independent URL you create in the app; can target one device or all. Max 10 per device. |

Both secrets are shown in the app. Store yours in an environment variable:
```bash
export NTF_SECRET="ntf_dev_xxxxxxxxxxxx"
curl -s -X POST "https://api.notifikations.com/api/v1/$NTF_SECRET" -d "Done"
```

---

## Scheduling

Add `send_at` (ISO 8601) to deliver later. Response includes a `jobId` you can use to cancel.

```bash
curl -X POST https://api.notifikations.com/api/v1/YOUR_SECRET \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Reminder",
    "message": "Stand-up in 5 minutes",
    "send_at": "2026-04-01T09:55:00Z"
  }'
```

Delivery precision is approximately ±1 minute. Max 10 pending scheduled jobs per webhook URL.

---

## Response codes

| Status | Body | Meaning |
|--------|------|---------|
| `200` | `{"success":true,"apnsId":"…"}` | Delivered to one device. |
| `200` | `{"success":true,"sent":2,"failures":0}` | User-secret fan-out result. |
| `400` | `{"error":"message is required"}` | Missing required field. |
| `404` | `{"error":"webhook not found"}` | Secret not registered — check URL. |
| `502` | `{"error":"…"}` | APNs rejected the notification. |

---

## Integration recipes

### Python (stdlib only)
```python
import urllib.request, json

def notify(message, title=None, secret="YOUR_SECRET"):
    url = f"https://api.notifikations.com/api/v1/{secret}"
    payload = {"message": message}
    if title:
        payload["title"] = title
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data,
          headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req)

notify("Training finished — val_loss 0.042", title="Model")
```

### JavaScript / Node.js
```javascript
async function notify(message, title) {
  await fetch("https://api.notifikations.com/api/v1/YOUR_SECRET", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message, title }),
  });
}

await notify("Job finished", "Cron");
```

### GitHub Actions
```yaml
# .github/workflows/deploy.yml
steps:
  - uses: actions/checkout@v4
  - run: npm ci && npm run build

  - name: Notify on success
    if: success()
    run: |
      curl -s -X POST "https://api.notifikations.com/api/v1/${{ secrets.NTF_SECRET }}" \
        -H 'Content-Type: application/json' \
        -d '{"title":"Deploy succeeded 🚀","message":"${{ github.repository }} → ${{ github.ref_name }}"}'

  - name: Notify on failure
    if: failure()
    run: |
      curl -s -X POST "https://api.notifikations.com/api/v1/${{ secrets.NTF_SECRET }}" \
        -H 'Content-Type: application/json' \
        -d '{"title":"Build failed ❌","message":"${{ github.repository }} on ${{ github.ref_name }}"}'
```

Store the secret in **Settings → Secrets → Actions** as `NTF_SECRET`.

### Home Assistant
```yaml
# configuration.yaml
rest_command:
  notifikations_send:
    url: "https://api.notifikations.com/api/v1/YOUR_SECRET"
    method: POST
    content_type: "application/json"
    payload: '{"title":"{{ title }}","message":"{{ message }}"}'

# automation.yaml — notify when washing machine finishes
automation:
  - alias: "Washing machine done"
    trigger:
      - platform: state
        entity_id: sensor.washing_machine_power
        to: "0"
        for: "00:01:00"
    action:
      - service: rest_command.notifikations_send
        data:
          title: "Laundry done 👕"
          message: "Washing machine finished"
```

### Claude Code (notify when Claude finishes a task)
```json
// ~/.claude/settings.json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST https://api.notifikations.com/api/v1/YOUR_SECRET -H 'Content-Type: application/json' -d '{\"title\":\"Claude done\",\"message\":\"Task finished\"}'"
          }
        ]
      }
    ]
  }
}
```

### n8n
Add an **HTTP Request** node:
- Method: `POST`
- URL: `https://api.notifikations.com/api/v1/YOUR_SECRET`
- Body Content Type: JSON
- Body:
```json
{
  "title": "n8n workflow done",
  "message": "{{ $json.summary }}"
}
```

### Zapier
Add a **Webhooks by Zapier** action:
- Method: `POST`
- URL: `https://api.notifikations.com/api/v1/YOUR_SECRET`
- Payload Type: `JSON`
- Data: map `title` and `message` from the trigger step

### Bash one-liner (cron, Makefile, CI scripts)
```bash
# Add to the end of any long-running script
notify() { curl -s -X POST "https://api.notifikations.com/api/v1/$NTF_SECRET" \
  -H 'Content-Type: application/json' \
  -d "{\"title\":\"$1\",\"message\":\"$2\"}"; }

notify "Backup done" "$(date): 3.2 GB uploaded to S3"
```

---

## Interactive action buttons

Ask the user a yes/no question from anywhere:

```bash
curl -X POST https://api.notifikations.com/api/v1/YOUR_SECRET \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Deploy to production?",
    "message": "v2.4.1 is ready",
    "category": "YES_NO",
    "callback_url": "https://your-server.com/deploy-webhook"
  }'
```

When the user taps **Yes** or **No**, Notifikations POSTs `{"action":"yes"}` or `{"action":"no"}` to your `callback_url`. The `callback_url` is never stored by Notifikations.

Available categories: `YES_NO`, `APPROVE_DISMISS`, `CONFIRM`.

---

## Tips

- **Keep the secret in an env var** — never hard-code it in source files.
- **Use the user secret** if you want all your devices to receive the notification simultaneously.
- **Use `interruption-level: "time-sensitive"`** only for urgent alerts — it breaks through Focus mode.
- **Use `open_url`** to deep-link into an app or open a dashboard directly from the notification tap.
- **Named webhooks** (created in the app) are useful for sharing a single URL with a service without exposing your main device secret.
