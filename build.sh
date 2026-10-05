#!/usr/bin/env bash
set -e

if [ ! -d "_flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 _flutter
fi

export PATH="$PATH:$(pwd)/_flutter/bin"

flutter --version
flutter pub get
flutter build web --release --base-href / --pwa-strategy=none

# Flutter's generated worker is empty in this mode. Ship sw.js instead, and
# also replace flutter_service_worker.js so browsers still registered to the
# old worker install this one and drop the stale cache.
cp web/sw.js build/web/sw.js
BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
sed -i "s/__HASTVEDA_BUILD_ID__/${BUILD_ID}/g" build/web/sw.js
cp build/web/sw.js build/web/flutter_service_worker.js
