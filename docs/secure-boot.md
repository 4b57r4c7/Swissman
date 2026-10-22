# Secure Boot със собствени ключове

Ядрото на Swissman е самостоятелно EFI приложение и се подписва за Secure Boot
при всяко компилиране (`scripts/sign-kernel.sh`). Компютърът ти ще стартира само
ядра, подписани с твоя ключ.

## Кой създава ключовете

Всеки потребител има свои ключове. Инсталаторът (стъпка 4) ще ги създаде на
самия компютър, ще подпише инсталираното ядро с тях и ще ги запише във
firmware-а. Частните ключове не напускат компютъра и не минават през GitHub.

ISO-то от GitHub Actions е подписано с временни тестови ключове. Live
системата от него се стартира с изключен Secure Boot (или в Setup Mode), а
Secure Boot се включва след инсталацията.

Ръчната настройка по-долу е за случая, в който сам компилираш ISO-та и искаш
да ги подписваш със свой ключ.

## Как работи

- **PK** (Platform Key) и **KEK** (Key Exchange Key) управляват кой може да
  променя списъка с доверени ключове във firmware-а.
- **db** е ключът, с който се подписва ядрото. Firmware-ът стартира само
  EFI програми, подписани с ключ от db.
- Без ключ в Secrets CI подписва с временни тестови ключове. Такова ISO се
  зарежда нормално без Secure Boot, но с включен Secure Boot ще бъде отказано.
  Това е нарочно.

## Ръчна настройка за собствени компилации (веднъж)

1. Генерирай ключовете на компютър, на който имаш доверие (нужен е само `openssl`):

   ```sh
   tools/make-secureboot-keys.sh ~/swissman-keys
   ```

2. Добави публичните сертификати в репото:

   ```sh
   mkdir -p config/secureboot
   cp ~/swissman-keys/{PK,KEK,db}.crt config/secureboot/
   git add config/secureboot && git commit -m "Add Secure Boot certificates"
   ```

3. В GitHub отвори **Settings → Secrets and variables → Actions → New
   repository secret**. Създай `SECUREBOOT_DB_KEY` и постави цялото
   съдържание на `~/swissman-keys/db.key`.

4. Пази `PK.key` и `KEK.key` извън компютъра, например на USB, което държиш
   заключено. Те трябват само за смяна на ключовете.

След това всяко ISO се подписва с твоя db ключ. Сертификатите се записват и в
папка `keys/` на EFI дяла на ISO-то.

## Записване на ключовете във firmware-а

1. Във firmware setup (BIOS) изтрий текущите ключове на Secure Boot. Компютърът
   минава в **Setup Mode**.
2. Запиши `db.cer`, после `KEK.cer`, накрая `PK.cer` от папка `keys/` на USB-то
   със Swissman. Повечето firmware-и имат опция „Enroll from file“.
3. Включи Secure Boot.

Внимание: ако изтриеш ключовете на Microsoft, Windows и някои видео карти с
option ROM подписани от Microsoft може да спрат да се зареждат.
