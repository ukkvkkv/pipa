# Сторонние компоненты

Код Pipa распространяется по лицензии MIT (см. [LICENSE](LICENSE)).
Внутри `Pipa.app` лежат готовые программы и библиотеки других проектов —
каждая под своей лицензией. Исходники доступны по ссылкам ниже.

| Компонент | Версия в релизе | Лицензия | Исходники |
|---|---|---|---|
| ipatool-cpp | 1.1.1 | MIT | [Sorvigolova/ipatool](https://github.com/Sorvigolova/ipatool) |
| ideviceinstaller, ideviceinfo | 1.2.0 | GPL-2.0 | [libimobiledevice/ideviceinstaller](https://github.com/libimobiledevice/ideviceinstaller) |
| libimobiledevice | 1.4.0 | LGPL-2.1 | [libimobiledevice/libimobiledevice](https://github.com/libimobiledevice/libimobiledevice) |
| libimobiledevice-glue | 1.3.3 | LGPL-2.1 | [libimobiledevice/libimobiledevice-glue](https://github.com/libimobiledevice/libimobiledevice-glue) |
| libplist | 2.8.0 | LGPL-2.1 | [libimobiledevice/libplist](https://github.com/libimobiledevice/libplist) |
| libusbmuxd | 2.1.1 | LGPL-2.1 | [libimobiledevice/libusbmuxd](https://github.com/libimobiledevice/libusbmuxd) |
| libzip | 1.12 | BSD-3-Clause | [nih-at/libzip](https://github.com/nih-at/libzip) |
| OpenSSL | 3.6.5 | Apache-2.0 | [openssl/openssl](https://github.com/openssl/openssl) |
| libtatsu | 1.0.5 | LGPL-2.1 | [libimobiledevice/libtatsu](https://github.com/libimobiledevice/libtatsu) |

`ideviceinstaller` и `ideviceinfo` — отдельные программы, Pipa запускает их как
внешние процессы и не линкуется с ними. Они собраны из исходников по ссылкам
выше без изменений, статически со всеми библиотеками из таблицы (кроме
ipatool-cpp), скриптом [`vendor/idevice/build.sh`](vendor/idevice/build.sh) —
он же скачивает точные архивы исходников и сверяет их SHA-256.

Список популярных приложений (`AppsList.txt`) Pipa берёт из
[kda2495/IPA_Downloader](https://github.com/kda2495/IPA_Downloader) (MIT) —
лицензия этого проекта лежит в `vendor/ipatool/LICENSE-IPA_Downloader`.
