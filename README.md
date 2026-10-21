# Swissman

Swissman е лична, ориентирана към сигурността Linux операционна система, изградена изцяло от изходен код по модела на [Linux From Scratch](https://www.linuxfromscratch.org/).

Всичко се компилира в GitHub Actions, а крайният резултат е ISO файл за инсталация на реален хардуер или във виртуална машина.

## План

1. **Build pipeline и кросс-toolchain** в GitHub Actions.
2. **Базова система** от изходен код и ISO, което се тества в QEMU.
3. **Сигурност и криптиране**: LUKS2, Secure Boot със собствени ключове, hardened ядро, nftables, подписани обновления.
4. **Инсталатор и издания** в GitHub Releases.
