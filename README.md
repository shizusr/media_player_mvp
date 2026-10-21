# media_player_mvp

Flutter-медиаплеер: вставьте ссылку YouTube / .mp4 / .m3u8, получите карточку в сетке, нажмите, чтобы смотреть.

## Быстрый старт
Linux/macOS: `./setup.sh`
Windows: `setup.bat` (затем вручную добавить INTERNET в AndroidManifest.xml)

Потом: `flutter run`

## Требования
- Android: minSdk >= 21; для http-ссылок добавьте `android:usesCleartextTraffic="true"` в <application>
- Windows: включить Developer Mode
- Linux: `sudo apt install libmpv-dev mpv`

## Ограничение
YouTube отдаётся muxed-потоками (видео+звук вместе), максимум 720p.
