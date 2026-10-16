#!/usr/bin/env bash
set -euo pipefail

APP_ENV="$(printf '%s' "${APP_ENV:-production}" | tr '[:upper:]' '[:lower:]')"
if [[ "$APP_ENV" != "production" && "$APP_ENV" != "test" ]]; then
  echo "ERROR: APP_ENV must be production or test."
  exit 1
fi

if [ "$APP_ENV" = "test" ]; then
  required_vars="SUPABASE_URL SUPABASE_PUBLISHABLE_KEY TEST_FIREBASE_API_KEY TEST_FIREBASE_APP_ID TEST_FIREBASE_MESSAGING_SENDER_ID TEST_FIREBASE_PROJECT_ID TEST_FIREBASE_AUTH_DOMAIN TEST_FIREBASE_STORAGE_BUCKET TEST_FIREBASE_VAPID_KEY"
  for name in $required_vars; do
    if [ -z "${!name:-}" ]; then
      echo "ERROR: APP_ENV=test requires $name. Refusing to build with production fallbacks."
      exit 1
    fi
  done
fi

if [ ! -f "env.json" ]; then
  echo "ERROR: env.json is required as a source configuration file."
  exit 1
fi

if [ ! -d "_flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 _flutter
fi
export PATH="$PATH:$(pwd)/_flutter/bin"

flutter --version
flutter pub get

# Build-time defines contain only client-facing configuration. Never compile
# arbitrary env.json fields (which may include privileged server credentials).
python3 - <<'PY'
import json, os
with open("env.json", encoding="utf-8") as f:
    src = json.load(f)
app_env = os.environ.get("APP_ENV", "production").strip().lower()
public_keys = (
    "SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEY",
    "CASHFREE_ENV", "AWS_LAMBDA_CHAT_COMPLETION_URL",
    "AWS_LAMBDA_IMAGE_GENERATION_URL", "MIXPANEL_TOKEN",
)
test_keys = (
    "TEST_FIREBASE_API_KEY", "TEST_FIREBASE_APP_ID",
    "TEST_FIREBASE_MESSAGING_SENDER_ID", "TEST_FIREBASE_PROJECT_ID",
    "TEST_FIREBASE_AUTH_DOMAIN", "TEST_FIREBASE_STORAGE_BUCKET",
    "TEST_FIREBASE_VAPID_KEY",
)
def usable(value):
    if not isinstance(value, str):
        return ""
    value = value.strip()
    upper = value.upper()
    if not value or upper.startswith(("COPY_OF_", "YOUR_", "YOUR-")):
        return ""
    return value

defines = {"APP_ENV": app_env}
for key in public_keys:
    value = usable(os.environ.get(key))
    if not value and app_env == "production":
        value = usable(src.get(key)) or usable(src.get(key + "_FALLBACK"))
    if value:
        defines[key] = value

if app_env == "test":
    for key in test_keys:
        value = usable(os.environ.get(key))
        if not value:
            raise SystemExit("ERROR: missing required test setting: " + key)
        defines[key] = value
    if not usable(os.environ.get("SUPABASE_URL")) or not usable(os.environ.get("SUPABASE_PUBLISHABLE_KEY")):
        raise SystemExit("ERROR: test Supabase settings must be supplied explicitly.")

# Keep the bundled env.json for legacy runtime readers, but reduce it to the
# small client-facing allowlist. This prevents unrelated secrets in the source
# file from being copied into the web bundle or APK.
asset = {}
for key in public_keys:
    value = usable(os.environ.get(key))
    if not value and app_env == "production":
        value = usable(src.get(key)) or usable(src.get(key + "_FALLBACK"))
    if value:
        asset[key] = value
with open("env.json", "w", encoding="utf-8") as f:
    json.dump(asset, f)
with open("web-defines.json", "w", encoding="utf-8") as f:
    json.dump(defines, f)
print("Prepared client-safe configuration for", app_env, "build.")
PY

flutter build web --release --base-href / --pwa-strategy=none \
  --dart-define-from-file=web-defines.json

cp web/sw.js build/web/sw.js
cp web/firebase-messaging-sw.js build/web/firebase-messaging-sw.js
python3 - <<'PY'
import json, os
path = "build/web/firebase-messaging-sw.js"
with open(path, encoding="utf-8") as f:
    content = f.read()
app_env = os.environ.get("APP_ENV", "production").strip().lower()
if app_env == "test":
    mapping = {
        "__FIREBASE_API_KEY__": os.environ["TEST_FIREBASE_API_KEY"],
        "__FIREBASE_APP_ID__": os.environ["TEST_FIREBASE_APP_ID"],
        "__FIREBASE_MESSAGING_SENDER_ID__": os.environ["TEST_FIREBASE_MESSAGING_SENDER_ID"],
        "__FIREBASE_PROJECT_ID__": os.environ["TEST_FIREBASE_PROJECT_ID"],
        "__FIREBASE_AUTH_DOMAIN__": os.environ["TEST_FIREBASE_AUTH_DOMAIN"],
        "__FIREBASE_STORAGE_BUCKET__": os.environ["TEST_FIREBASE_STORAGE_BUCKET"],
    }
else:
    mapping = {
        "__FIREBASE_API_KEY__": "AIzaSyBHbakAGVgamWXBBL_mFHCicOEhl61Z8FI",
        "__FIREBASE_APP_ID__": "1:412267977624:web:c85847f932d18ec69869ed",
        "__FIREBASE_MESSAGING_SENDER_ID__": "412267977624",
        "__FIREBASE_PROJECT_ID__": "hastveda-notifications",
        "__FIREBASE_AUTH_DOMAIN__": "hastveda-notifications.firebaseapp.com",
        "__FIREBASE_STORAGE_BUCKET__": "hastveda-notifications.appfirebasestorage.app",
    }
for old, new in mapping.items():
    content = content.replace(old, json.dumps(new)[1:-1])
if "__FIREBASE_" in content:
    raise SystemExit("ERROR: unresolved Firebase config placeholder; refusing build.")
with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PY

# Verify the published worker has no unresolved Firebase placeholders.
if grep -q '__FIREBASE_' build/web/firebase-messaging-sw.js; then
  echo "ERROR: unresolved Firebase placeholders in built service worker."
  exit 1
fi
BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
sed -i "s/__HASTVEDA_BUILD_ID__/${BUILD_ID}/g" build/web/sw.js
cp build/web/sw.js build/web/flutter_service_worker.js
touch build/web/.nojekyll
