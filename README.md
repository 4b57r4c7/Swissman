# Swissman

Swissman е лична, ориентирана към сигурността Linux операционна система, изградена изцяло от изходен код по модела на [Linux From Scratch](https://www.linuxfromscratch.org/).

Всичко се компилира в GitHub Actions, а крайният резултат е ISO файл за инсталация на реален хардуер или във виртуална машина.

## План

1. **Build pipeline и кросс-toolchain** в GitHub Actions.
2. **Базова система** от изходен код и ISO, което се тества в QEMU.
3. **Сигурност и криптиране**: LUKS2, Secure Boot със собствени ключове, hardened ядро, nftables, подписани обновления.
4. **Инсталатор и издания** в GitHub Releases.

## Основни решения

- Пакетите и инструкциите следват [LFS 13.1-systemd](https://www.linuxfromscratch.org/lfs/view/13.1-systemd/). От версия 13.0 LFS поддържа само вариант със systemd.
- Ядрото е от LTS серията **6.18** (поддръжка до декември 2028), а не версията от книгата. Архивът се проверява с GPG подписа на поддържащите stable клона.
- Командите за глава 8 (`scripts/stage3-chroot/`) се генерират автоматично от изходния код на книгата с `tools/update-lfs-scripts.sh`, за да съвпадат точно с LFS.
- Ядрото носи вграден initramfs и само по себе си е EFI приложение, така че ISO-то стартира директно чрез UEFI, без отделен bootloader. Това по-късно позволява целият boot път да се подпише за Secure Boot с един подпис.
- Конфигурацията на ядрото (`config/kernel/swissman.config`) включва hardening настройки от Kernel Self Protection Project, задължителен lockdown и подписани модули.
- Ядрото се подписва за Secure Boot със собствени ключове, без Microsoft и без shim. Виж [docs/secure-boot.md](docs/secure-boot.md).
