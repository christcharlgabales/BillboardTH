#!/bin/bash
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH=$PWD/flutter/bin:$PATH
flutter config --no-analytics
flutter doctor
flutter pub get
flutter build web --release --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
