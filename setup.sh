#!/usr/bin/env bash
# Генерирует platform-папки (android, windows, linux), добавляет INTERNET и ставит зависимости.
set -e
flutter create . --platforms=android,windows,linux --project-name media_player_mvp
rm -f test/widget_test.dart

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ] && ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
  sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET" />\n    <application|' "$MANIFEST"
  echo "INTERNET permission добавлен в AndroidManifest.xml"
fi

flutter pub get
echo "Готово. Запуск: flutter run"
