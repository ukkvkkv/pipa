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
| libzip | 1.11.4 | BSD-3-Clause | [nih-at/libzip](https://github.com/nih-at/libzip) |
| OpenSSL | 3.6 | Apache-2.0 | [openssl/openssl](https://github.com/openssl/openssl) |
| xz (liblzma) | 5.8 | 0BSD | [tukaani-project/xz](https://github.com/tukaani-project/xz) |
| zstd | 1.5.7 | BSD-3-Clause | [facebook/zstd](https://github.com/facebook/zstd) |

`ideviceinstaller` и `ideviceinfo` — отдельные программы, Pipa запускает их как
внешние процессы и не линкуется с ними. Они собраны Homebrew из исходников по
ссылкам выше без изменений.

Список популярных приложений (`AppsList.txt`) Pipa берёт из
[kda2495/IPA_Downloader](https://github.com/kda2495/IPA_Downloader) (MIT) —
лицензия этого проекта лежит в `vendor/ipatool/LICENSE-IPA_Downloader`.
