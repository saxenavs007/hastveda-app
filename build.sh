#!/usr/bin/env bash
set -e

if [ ! -d "_flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 _flutter
fi

export PATH="$PATH:$(pwd)/_flutter/bin"

flutter --version
flutter pub get

# Compile only the public Supabase client values. The rest of env.json
# (service-account secrets and provider keys) stays out of the web bundle.
python3 - <<'PY'
import json
src = json.load(open("env.json", encoding="utf-8"))
keys = (
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SUPABASE_PUBLISHABLE_KEY",
    "CASHFREE_ENV",
)
def usable(value):
    if not isinstance(value, str):
        return ""
    text = value.strip()
    upper = text.upper()
    if not text or upper.startswith("COPY_OF_") or upper.startswith("YOUR_") or upper.startswith("YOUR-"):
        return ""
    return text
data = {}
for key in keys:
    value = usable(src.get(key)) or usable(src.get(key + "_FALLBACK"))
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
BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
sed -i "s/__HASTVEDA_BUILD_ID__/${BUILD_ID}/g" build/web/sw.js
cp build/web/sw.js build/web/flutter_service_worker.js
