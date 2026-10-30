# Нативная Android-сборка

Этот APK экспортируется непосредственно из Godot, без WebView/Capacitor. Старые файлы React сохранены в `src/` как предыдущий прототип и исключены из APK.

## Проверяемое окружение

- Godot **4.6.3 stable**, обычная сборка GDScript, и экспортные шаблоны ровно **4.6.3**.
- OpenJDK **17** рекомендован документацией Godot; локальный экспорт допускает более новый Java runtime при наличии `java` и `keytool`.
- Android platform-tools, SDK Platform **36**, build-tools **36.0.0**.
- Linux x86_64: `bash`, `curl`, `unzip`, `python3`, `rg`, `timeout`.
- APK: `com.techempire.game`, version 0.1.0/code 1, ARM64 и x86_64, Android 7.0/API24+, Compatibility renderer.

NDK, CMake, Gradle и Android Studio не требуются для этого стандартного экспорта без нативных плагинов. Для custom Gradle/AAB экспорта понадобятся дополнительные компоненты.

В preset отключён редакторский флаг `runnable`: он запускает постоянный опрос подключённых устройств через adb, ненужный пакетной сборке. Это не влияет на запуск установленной игры или экспорт. Для кнопки быстрого запуска на телефон в редакторе включите Runnable в окне Export после настройки устройства.

## Локальная сборка

Из корня репозитория:

```bash
# Установить Godot 4.6.3 заранее; GODOT_BIN может указывать на его бинарник.
bash tools/android/bootstrap.sh
bash tools/build_android.sh
```

Загрузки, SDK, шаблоны, настройки редактора и debug keystore по умолчанию хранятся рядом с репозиторием в `../.tech-empire-tools/`, а не в исходном коде. Путь меняется через `TECH_EMPIRE_TOOLS_DIR`. Можно задать `ANDROID_HOME`, `JAVA_HOME`, `GODOT_BIN`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`. Не отключайте TLS или сетевой прокси окружения. bootstrap сохраняет прокси и передаёт его sdkmanager; лицензии Android SDK принимаются при установке пакетов.

Результат: `artifacts/TECH-EMPIRE-debug.apk`, SHA256 рядом, логи `artifacts/logs/`. Скрипт импортирует проект, запускает все GDScript-наборы `tests/test_*.gd`, экспортирует APK, проверяет его подпись, package metadata и наличие ARM64-библиотеки Godot. Ошибка любой команды или ошибка GDScript прерывает сборку.

Экспорт идёт во временный APK; окончательный файл заменяется только после проверок. Если новая сборка завершилась ошибкой, сохранённый APK относится к предыдущей успешной сборке. CI не публикует APK после неудачного шага проверки.

Скрипт сборки также проверяет zip alignment 16 KiB и упакованные игровые файлы. Отдельно эту проверку можно повторить:

```bash
python3 tools/android/inspect_apk.py artifacts/TECH-EMPIRE-debug.apk --report artifacts/logs/apk-resources.json
```

Она сравнивает каждый JSON/XML из `data/` с APK, проверяет сцены, основные скрипты, обе нативные библиотеки и отсутствие старого веб-прототипа/тестов внутри приложения. Эта статическая проверка не заменяет установку и запуск на Android.

## Установка на телефон

Прямая ссылка без входа в GitHub: [TECH-EMPIRE-debug.apk](https://github.com/egorhorobrov852-ux/TechEmpire/releases/download/v0.1.0-preview.1/TECH-EMPIRE-debug.apk). Откройте её в браузере телефона, дождитесь скачивания и запустите файл из «Загрузок». APK и архив исходников также доступны на [странице предварительной версии](https://github.com/egorhorobrov852-ux/TechEmpire/releases/tag/v0.1.0-preview.1).

1. Скопировать `TECH-EMPIRE-debug.apk` на Android 7.0+ с ARM64.
2. Разрешить установку из выбранного файлового менеджера/браузера, открыть APK, установить.
3. Игра работает офлайн, регистрация и компьютер для последующих запусков не нужны.

При подключённом устройстве:

```bash
adb devices
adb install -r artifacts/TECH-EMPIRE-debug.apk
adb shell am start -n com.techempire.game/com.godot.game.GodotAppLauncher
```

Стандартный debug-сертификат предназначен для разработки. Если предыдущая версия подписана другим ключом, Android откажет в обновлении; удаление прежнего приложения стирает его локальные сохранения. Сначала сделайте резервную копию прогресса, если он нужен.

## GitHub Actions

Workflow `.github/workflows/build-apk.yml` запускается вручную, для PR и push в main/feat/**. Он устанавливает Java17, Godot4.6.3, SDK и соответствующие шаблоны, выполняет проверки и экспорт. APK и SHA256 появляются в артефакте `TECH-EMPIRE-Android-debug`; диагностические логи сохраняются даже при ошибке. Наличие workflow не означает, что удалённый запуск уже выполнялся: фактический статус проверок фиксируется в `docs/VERIFICATION.md`.

Нативная версия находится в ветке `feat/playable-android` и draft PR #1; `main` сохраняет предыдущий прототип до проверки изменений. Для ручного запуска в GitHub Actions выберите эту ветку в поле Branch. Через CLI:

```bash
gh workflow run build-apk.yml --ref feat/playable-android
```

Фактически прошедшая нативная CI-сборка: https://github.com/egorhorobrov852-ux/TechEmpire/actions/runs/40998681203 . Артефакт APK доступен 14 дней; после истечения срока запустите workflow повторно.

## Release и магазин

Release APK использует `godot --headless --path . --export-release Android artifacts/TECH-EMPIRE-release.apk` после установки release credentials через переменные окружения Godot или локальные секретные настройки экспорта. Никогда не добавляйте release keystore и пароль в Git или APK. Не используйте debug key для магазина. Для Google Play включите Gradle build и формат AAB в отдельном release preset, установите Android source template, настройте ваш applicationId, versionCode, подпись и требования магазина. Текущая задача производит sideload debug APK; публикация в магазине не выполняется.

Документация: https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html
