#!/usr/bin/env bash
set -e

# Clone Flutter stable SDK if not already present
if [ ! -d "_flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 _flutter
fi

export PATH="$PATH:\`pwd\`/_flutter/bin"

flutter doctor
flutter pub get
flutter build web --release