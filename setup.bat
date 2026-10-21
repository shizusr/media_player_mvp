@echo off
flutter create . --platforms=android,windows,linux --project-name media_player_mvp
if exist test\widget_test.dart del test\widget_test.dart
echo.
echo ВАЖНО: добавьте в android\app\src\main\AndroidManifest.xml перед тегом ^<application^>:
echo     ^<uses-permission android:name="android.permission.INTERNET" /^>
echo.
flutter pub get
echo Готово. Запуск: flutter run
