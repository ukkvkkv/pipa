<div align="center">

<img src="assets/logo.png" width="160" alt="Иконка Pipa">

# Pipa

**Скачивает приложения из App Store в `.ipa` и ставит их на iPhone по кабелю.**<br>
Всё в одном окне, на родном macOS — без Терминала и без танцев с бубном.

[![Скачать Pipa](https://img.shields.io/badge/Скачать-Pipa.dmg-4C86F9?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/ukkvkkv/pipa/releases/latest/download/Pipa.dmg)

[![Последний релиз](https://img.shields.io/github/v/release/ukkvkkv/pipa?style=flat-square&color=4C86F9&label=версия)](https://github.com/ukkvkkv/pipa/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?style=flat-square&logo=apple)
![Universal](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-111?style=flat-square)
![Swift](https://img.shields.io/badge/SwiftUI-Liquid%20Glass-F05138?style=flat-square&logo=swift&logoColor=white)
[![MIT](https://img.shields.io/badge/лицензия-MIT-6E9BFF?style=flat-square)](LICENSE)

<img src="docs/downloads.jpg" width="720" alt="Окно Pipa с загрузками">

</div>

---

## Зачем это

Вернуть на iPhone приложение, которое **удалили из App Store** (банки, платёжные
сервисы, маркетплейсы) или которого **нет в регионе** твоего аккаунта, — если оно
когда-то было у тебя в покупках. Или скачать `.ipa` про запас, пока приложение
ещё в магазине.

Pipa скачивает установочный файл прямо с серверов Apple от имени твоего Apple ID
и ставит его на телефон. Никаких взломов: только то, на что у аккаунта есть права.

## Что умеет

|  |  |
|---|---|
| 🔎 **Поиск** | по названию или по ID из ссылки App Store |
| ⬇️ **Загрузка** | очередь, проценты и мегабайты по ходу, отмена и повтор |
| 🆓 **Бесплатные** | «Скачать» сам получает лицензию, если её ещё нет |
| 📚 **Библиотека** | все скачанные `.ipa`: версия, минимальная iOS, размер, аккаунт |
| 📱 **Установка** | на iPhone по USB одной кнопкой, с проверкой версии iOS |
| 👥 **Аккаунты** | несколько Apple ID, переключение в настройках |
---

## Установка

1. Скачай **[Pipa.dmg](https://github.com/ukkvkkv/pipa/releases/latest/download/Pipa.dmg)**.
2. Открой его и перетащи **Pipa** в папку **Программы**.
3. Первый запуск. Pipa не нотаризована в Apple (это хобби-проект без платного
   аккаунта разработчика), поэтому macOS её сначала не пустит:
   - открой Pipa — появится предупреждение, нажми **Готово**;
   - **Системные настройки → Конфиденциальность и безопасность** → внизу
     **«Всё равно открыть»** → подтверди паролем.

   Или одной командой в Терминале:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Pipa.app
   ```
> **Требования:** macOS 14 Sonoma или новее, любой Mac — Apple Silicon или Intel.

---

## Как пользоваться

### 1. Войти в Apple ID

Нажми **Войти…** и введи Apple ID и пароль — тот аккаунт, на котором числятся
нужные приложения. Apple попросит код подтверждения:

- он придёт на твои устройства всплывающим окном, или
- на iPhone: **Настройки → [твоё имя] → Вход и безопасность → Получить код проверки**.

> [!IMPORTANT]
> Если на аккаунте включены **аппаратные ключи безопасности**, вход не пройдёт —
> их придётся выключить.

Пароль Pipa не хранит: он передаётся напрямую в `ipatool`, а тот получает у Apple
токен сессии. Аккаунтов можно добавить несколько — **⚙︎ Настройки → Добавить аккаунт…**

### 2. Найти и скачать

Вкладка **🔎 Поиск**: введи название или числовой ID приложения (он есть в ссылке
`apps.apple.com/…/id1234567890`) и нажми **Скачать** справа от результата.

- Прогресс видно по кружку в панели сверху; клик по нему открывает список
  загрузок.
- Правый клик по приложению: **Получить без загрузки** (только добавить в
  покупки), **Скопировать ID**, **Открыть в App Store**.
- Галочка ✓ у приложения — его уже скачивали с этого аккаунта.

Файлы ложатся в **`~/Pipa`**. Папку можно сменить в настройках.

### 3. Поставить на iPhone

1. Подключи iPhone кабелем и разблокируй его. При первом подключении ответь
   **«Доверять»** на телефоне.
2. Внизу окна появится имя телефона и версия iOS.
3. Вкладка **▦ Библиотека** → у нужного файла кнопка **На iPhone**.

Если приложению нужна iOS новее, чем на телефоне, кнопка будет неактивна.
Без кабеля тоже можно: отправь `.ipa` на iPhone через **AirDrop**, и он
установится сам.

---

## Вопросы

<details>
<summary><b>«Приложение не приобретено этим аккаунтом»</b></summary>

Apple отдаёт `.ipa` только тем аккаунтам, у которых приложение есть в покупках.
Бесплатные Pipa «покупает» сама, но только пока приложение ещё продаётся в
регионе твоего Apple ID. Если его убрали из магазина — скачать получится только
с аккаунта, который успел его получить раньше. Регион задаёт сам Apple ID, в Pipa
такой настройки нет.
</details>

<details>
<summary><b>«Сессия истекла — войдите в аккаунт заново»</b></summary>

Токен Apple живёт не вечно. **⚙︎ Настройки → Выйти**, затем войти снова с кодом.
</details>

<details>
<summary><b>Телефон не появляется внизу окна</b></summary>

Разблокируй iPhone, проверь, что ответил «Доверять», попробуй другой кабель или
порт. Установщик работает через тот же сервис, что Finder, так что если Finder
видит телефон — увидит и Pipa.
</details>

<details>
<summary><b>Можно ли поставить приложение на чужой iPhone?</b></summary>

`.ipa` из App Store привязан к Apple ID, с которого его скачали. Запустится он на
телефоне, где в App Store выполнен вход в этот же аккаунт (или после входа в него).
</details>

<details>
<summary><b>Безопасно ли давать пароль?</b></summary>

Pipa — открытый код, всё в этом репозитории. Пароль уходит только в `ipatool`,
а тот ходит только на серверы Apple. Сама Pipa ходит в сеть только за иконками приложений
(тоже к Apple).
</details>

---

## Сборка из исходников

Нужны только Xcode Command Line Tools (`xcode-select --install`) с macOS SDK 26.

```bash
./build.command
```

Получится `Pipa.app` рядом со скриптом. `./make_dmg.command` соберёт его же и
упакует в `Pipa.dmg`. Иконка рисуется кодом: `swift assets/draw_icon.swift assets/logo.png`.

`ideviceinstaller` и `ideviceinfo` лежат в `vendor/idevice/` готовыми — universal,
статически собранные для macOS 11+. Пересобрать их из исходников (при обновлении
версий): `brew install autoconf automake libtool pkg-config cmake`, затем
`vendor/idevice/build.sh`.

<details>
<summary>Что где лежит</summary>

```
Sources/Pipa/     интерфейс на SwiftUI и логика
  IPATool.swift     обёртка над ipatool: вход, поиск, покупка, загрузка
  AppModel.swift    состояние приложения, очередь загрузок, установка
  ContentView.swift окно, панель, вход в Apple ID
  StoreViews.swift  поиск
  LocalViews.swift  библиотека, загрузки, настройки
  Compat.swift      Liquid Glass на macOS 26 и замена ему на 14–15
assets/           иконка и её генератор
vendor/ipatool/   готовые бинарники ipatool-cpp (arm64 и x86_64)
vendor/idevice/   ideviceinstaller и ideviceinfo + build.sh, который их собирает
build.command     сборка Pipa.app
make_dmg.command  сборка Pipa.dmg
```
</details>

---

## Поддержать

Pipa бесплатная. Если она тебе пригодилась — можно закинуть на кофе 💙

[![Поддержать через CloudTips](https://img.shields.io/badge/Поддержать-CloudTips-FF4F8B?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://pay.cloudtips.ru/p/ebe1daa2)

Кнопка «Поддержать» есть и в настройках приложения.

## Лицензия

Код Pipa — [MIT](LICENSE).

Pipa не связана с Apple. App Store, iPhone и macOS — товарные знаки Apple Inc.
Скачивай только то, на что у твоего аккаунта есть права.

<div align="center">
<br>
<sub>Сделано на Mac, для Mac 💙</sub>
</div>
