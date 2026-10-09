#!/bin/bash
set -euo pipefail

# Собирает ideviceinstaller и ideviceinfo из исходников: universal
# (arm64 + x86_64), статически со всеми библиотеками, для macOS 11+.
# Готовые пакеты Homebrew не годятся: они только под arm64 и под ту macOS,
# на которой собраны. Результат кладётся рядом со скриптом и лежит в git —
# пересобирать нужно только при обновлении версий ниже.
#
# Нужны: Command Line Tools и `brew install autoconf automake libtool pkg-config cmake`.

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(getconf DARWIN_USER_CACHE_DIR)pipa/idevice"
MIN_OS=11.0
SDK="$(xcrun --sdk macosx --show-sdk-path)"
JOBS="$(sysctl -n hw.ncpu)"

# Те же версии и контрольные суммы, что в формулах Homebrew.
SOURCES=(
  "https://github.com/openssl/openssl/releases/download/openssl-3.6.5/openssl-3.6.5.tar.gz a2157c2830efdec3788939b00c9b0638306d3f0bbb76dc4832ee503bb397df98"
  "https://libzip.org/download/libzip-1.12.tar.xz 376908d0f0fda13180a19fdc4f7062a1abfb59e09ca07a392d361253b8e60c2b"
  "https://github.com/libimobiledevice/libplist/releases/download/2.8.0/libplist-2.8.0.tar.bz2 b1f59f7634c58b2481325a23ff4e3bf51574a42d868cbe466d2b39b04550752a"
  "https://github.com/libimobiledevice/libimobiledevice-glue/releases/download/1.3.3/libimobiledevice-glue-1.3.3.tar.bz2 920ce01382a32695f49b23292b4979a03f0afd16c58e8755d8b7f41804acc1a9"
  "https://github.com/libimobiledevice/libusbmuxd/releases/download/2.1.1/libusbmuxd-2.1.1.tar.bz2 5546f1aba1c3d1812c2b47d976312d00547d1044b84b6a461323c621f396efce"
  "https://github.com/libimobiledevice/libtatsu/releases/download/1.0.5/libtatsu-1.0.5.tar.bz2 536fa228b14f156258e801a7f4d25a3a9dd91bb936bf6344e23171403c57e440"
  "https://github.com/libimobiledevice/libimobiledevice/releases/download/1.4.0/libimobiledevice-1.4.0.tar.bz2 23cc0077e221c7d991bd0eb02150a0d49199bcca1ddf059edccee9ffd914939d"
  "https://github.com/libimobiledevice/ideviceinstaller/releases/download/1.2.0/ideviceinstaller-1.2.0.tar.bz2 26115288e50d003bbb7d23c05441c54ea69b255974303bfd44fef6943e042f94"
)

mkdir -p "$WORK/src"
for entry in "${SOURCES[@]}"; do
  url="${entry% *}" sum="${entry#* }"
  file="$WORK/src/$(basename "$url")"
  [[ -f "$file" ]] || curl -fL --retry 3 -o "$file" "$url"
  echo "$sum  $file" | shasum -a 256 -c --quiet
done

unpack() {  # unpack <архив> <каталог сборки> → печатает путь к исходникам
  local dir="$2/$(basename "$1" | sed -E 's/\.tar\.(gz|bz2|xz)$//')"
  rm -rf "$dir"; tar -xf "$1" -C "$2"; echo "$dir"
}

build_arch() {
  local arch="$1" host
  case "$arch" in arm64) host=aarch64-apple-darwin ;; x86_64) host=x86_64-apple-darwin ;; esac
  local P="$WORK/prefix-$arch" B="$WORK/build-$arch"
  rm -rf "$P" "$B"; mkdir -p "$P/lib/pkgconfig" "$B"

  export CC="clang -arch $arch" CXX="clang++ -arch $arch"
  export CFLAGS="-isysroot $SDK -mmacosx-version-min=$MIN_OS -O2"
  export CXXFLAGS="$CFLAGS"
  export CPPFLAGS="-I$P/include"
  export LDFLAGS="-isysroot $SDK -mmacosx-version-min=$MIN_OS -L$P/lib"
  # Только свои .pc: библиотеки Homebrew не должны попасть в сборку.
  export PKG_CONFIG_LIBDIR="$P/lib/pkgconfig" PKG_CONFIG_PATH=""
  export MACOSX_DEPLOYMENT_TARGET="$MIN_OS"
  # При кросс-сборке configure не может запустить проверку malloc(0) и
  # подставляет rpl_malloc, которого нет. На macOS malloc(0) честный.
  export ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes
  local conf=(--prefix="$P" --host="$host" --disable-shared --enable-static)

  # libcurl для libtatsu — системный (в SDK нет его .pc).
  printf 'Name: libcurl\nDescription: system\nVersion: 8.0.0\nLibs: -lcurl\nCflags:\n' > "$P/lib/pkgconfig/libcurl.pc"

  local s
  s="$(unpack "$WORK/src/openssl-3.6.5.tar.gz" "$B")"
  (cd "$s" && ./Configure "darwin64-$arch-cc" no-shared no-tests no-docs no-apps no-module \
      --prefix="$P" --libdir=lib -mmacosx-version-min=$MIN_OS -isysroot "$SDK" >/dev/null \
    && make -j"$JOBS" >/dev/null && make install_sw >/dev/null)

  s="$(unpack "$WORK/src/libzip-1.12.tar.xz" "$B")"
  cmake -S "$s" -B "$s/b" -DCMAKE_INSTALL_PREFIX="$P" -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_OS -DCMAKE_OSX_SYSROOT="$SDK" -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF -DENABLE_OPENSSL=OFF \
    -DENABLE_GNUTLS=OFF -DENABLE_COMMONCRYPTO=OFF \
    -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF >/dev/null
  cmake --build "$s/b" -j"$JOBS" >/dev/null && cmake --install "$s/b" >/dev/null

  for pkg in libplist-2.8.0 libimobiledevice-glue-1.3.3 libusbmuxd-2.1.1 libtatsu-1.0.5; do
    s="$(unpack "$WORK/src/$pkg.tar.bz2" "$B")"
    (cd "$s" && ./configure "${conf[@]}" --without-cython >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null)
  done

  s="$(unpack "$WORK/src/libimobiledevice-1.4.0.tar.bz2" "$B")"
  (cd "$s" && LIBS="-lcurl -lz" ./configure "${conf[@]}" --without-cython >/dev/null \
    && make -j"$JOBS" >/dev/null && make install >/dev/null)

  s="$(unpack "$WORK/src/ideviceinstaller-1.2.0.tar.bz2" "$B")"
  (cd "$s" && LIBS="-lcurl -lz" ./configure "${conf[@]}" >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null)
}

for arch in arm64 x86_64; do
  echo "Сборка $arch…"
  build_arch "$arch"
done

for tool in ideviceinstaller ideviceinfo; do
  lipo -create "$WORK/prefix-arm64/bin/$tool" "$WORK/prefix-x86_64/bin/$tool" -output "$HERE/$tool"
  strip -x "$HERE/$tool"
done

echo
for tool in ideviceinstaller ideviceinfo; do
  echo "$tool: $(lipo -archs "$HERE/$tool"), $(du -h "$HERE/$tool" | cut -f1)"
  otool -L "$HERE/$tool" | tail -n +2
done
