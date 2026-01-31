# Push Notifications Spec (Chats First)

## Goals
- Deliver push notifications for new chat messages.
- Register/unregister iOS device tokens when a user signs in or out.
- Keep the design extensible for future notification types (photos, events, etc.).

## iOS Client Summary
- The iOS app requests notification authorization on authentication and registers for APNs.
- Device tokens are sent to the server with environment and platform metadata.
- On logout, the app unregisters the device token.

## API Endpoints

### Register device token
`POST /api/notifications/push/register`

**Request body**
```json
{
  "token": "<apns-device-token>",
  "platform": "ios",
  "environment": "development" | "production"
}
```

**Response body**
```json
{
  "success": true,
  "error": null
}
```

### Unregister device token
`POST /api/notifications/push/unregister`

**Request body**
```json
{
  "token": "<apns-device-token>",
  "platform": "ios",
  "environment": "development" | "production"
}
```

**Response body**
```json
{
  "success": true,
  "error": null
}
```

## Data Model (Server)

### Suggested table: `push_device_tokens`
| Column | Type | Notes |
| --- | --- | --- |
| id | UUID/int | Primary key |
| user_id | UUID/int | FK to users |
| token | string | APNs token |
| platform | string | `ios` for now |
| environment | string | `development` or `production` |
| created_at | timestamp | default now |
| updated_at | timestamp | updated on upsert |
| last_seen_at | timestamp | optional, update on register |
| is_active | boolean | optional soft delete flag |

**Behavior**
- Register endpoint should upsert `(user_id, token, platform, environment)`.
- Unregister endpoint can delete the row or set `is_active=false`.

## Notification Trigger (Chats)

### When to send
- On creation of a new chat message.
- Only notify users **other than** the message sender.
- Optional: skip notification if the user is currently connected to chat WebSocket and marked as active.

### Payload (APNs)
Example APNs JSON payload:
```json
{
  "aps": {
    "alert": {
      "title": "New message",
      "body": "<sender name>: <message excerpt>"
    },
    "sound": "default",
    "badge": 1,
    "category": "chat_message"
  },
  "data": {
    "type": "chat_message",
    "message_id": 123,
    "sender_id": 456,
    "sender_name": "Pat",
    "thread_id": null
  }
}
```

### APNs headers
- `apns-topic`: bundle identifier (e.g., `com.familyportal.app`).
- `apns-push-type`: `alert`.
- `apns-priority`: `10`.
- `apns-expiration`: optional (e.g., 24 hours).

## Server Flow (Chats)
1. Chat message is created and stored.
2. Query device tokens for all recipients except sender.
3. For each token:
   - Determine environment (development/production) and send to APNs accordingly.
   - Track any APNs errors (e.g., unregistered token) and disable/remove token.

## Future Extensions
- Add `type` field to register endpoint to allow topic subscriptions (e.g., `chat`, `photos`).
- Add endpoints for notification preferences per user.
- Provide per-thread or per-family mute settings.
