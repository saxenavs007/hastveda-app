#!/usr/bin/env bash
set -e

APP_ENV="${APP_ENV:-production}"
if [ "$APP_ENV" = "test" ]; then
  required_vars="SUPABASE_URL SUPABASE_PUBLISHABLE_KEY TEST_FIREBASE_API_KEY TEST_FIREBASE_APP_ID TEST_FIREBASE_MESSAGING_SENDER_ID TEST_FIREBASE_PROJECT_ID TEST_FIREBASE_AUTH_DOMAIN TEST_FIREBASE_STORAGE_BUCKET TEST_FIREBASE_VAPID_KEY"
  for name in $required_vars; do
    if [ -z "${!name:-}" ]; then
      echo "ERROR: APP_ENV=test requires $name. Refusing to build with production fallbacks."
      exit 1
    fi
  done
fi

if [ ! -d "_flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 _flutter
fi

export PATH="$PATH:$(pwd)/_flutter/bin"

flutter --version
flutter pub get

# Compile only the public Supabase client values. The rest of env.json
# (service-account secrets and provider keys) stays out of the web bundle.
python3 - <<'PY'
import json, os
src = json.load(open("env.json", encoding="utf-8"))
keys = (
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SUPABASE_PUBLISHABLE_KEY",
    "CASHFREE_ENV",
)
app_env = os.environ.get("APP_ENV", "production").strip().lower()
test_keys = (
    "TEST_FIREBASE_API_KEY", "TEST_FIREBASE_APP_ID",
    "TEST_FIREBASE_MESSAGING_SENDER_ID", "TEST_FIREBASE_PROJECT_ID",
    "TEST_FIREBASE_AUTH_DOMAIN", "TEST_FIREBASE_STORAGE_BUCKET",
    "TEST_FIREBASE_VAPID_KEY",
)
def usable(value):
    if not isinstance(value, str):
        return ""
    text = value.strip()
    upper = text.upper()
    if not text or upper.startswith("COPY_OF_") or upper.startswith("YOUR_") or upper.startswith("YOUR-"):
        return ""
    return text
data = {"APP_ENV": app_env}
for key in keys:
    if app_env == "test":
        value = usable(os.environ.get(key))
    else:
        value = usable(os.environ.get(key)) or usable(src.get(key)) or usable(src.get(key + "_FALLBACK"))
    if value:
        data[key] = value
if app_env == "test":
    for key in test_keys:
        value = usable(os.environ.get(key))
        if value:
            data[key] = value
with open("web-defines.json", "w", encoding="utf-8") as handle:
    json.dump(data, handle)
print("web defines:", ", ".join(data) or "(none; runtime env.json fallback)")
PY

flutter build web --release --base-href / --pwa-strategy=none \
  --dart-define-from-file=web-defines.json

# Flutter's generated worker is empty in this mode. Ship sw.js instead, and
# also replace flutter_service_worker.js so browsers still registered to the
# old worker install this one and drop the stale cache.
cp web/sw.js build/web/sw.js
cp web/firebase-messaging-sw.js build/web/firebase-messaging-sw.js
if [ "$APP_ENV" = "test" ]; then
  python3 - <<'PY'
import json, os
path = "build/web/firebase-messaging-sw.js"
content = open(path, encoding="utf-8").read()
mapping = {
    "__FIREBASE_API_KEY__": os.environ["TEST_FIREBASE_API_KEY"],
    "__FIREBASE_APP_ID__": os.environ["TEST_FIREBASE_APP_ID"],
    "__FIREBASE_MESSAGING_SENDER_ID__": os.environ["TEST_FIREBASE_MESSAGING_SENDER_ID"],
    "__FIREBASE_PROJECT_ID__": os.environ["TEST_FIREBASE_PROJECT_ID"],
    "__FIREBASE_AUTH_DOMAIN__": os.environ["TEST_FIREBASE_AUTH_DOMAIN"],
    "__FIREBASE_STORAGE_BUCKET__": os.environ["TEST_FIREBASE_STORAGE_BUCKET"],
}
for old, new in mapping.items():
    content = content.replace(old, json.dumps(new)[1:-1])
if "__FIREBASE_" in content:
    raise SystemExit("Unresolved Firebase config placeholder; refusing test build.")
open(path, "w", encoding="utf-8").write(content)
PY
fi
BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
sed -i "s/__HASTVEDA_BUILD_ID__/${BUILD_ID}/g" build/web/sw.js
cp build/web/sw.js build/web/flutter_service_worker.js
