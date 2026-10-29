#!/bin/bash
set -e
trap 'echo "Не удалось запустить лаунчер. Проверь адрес сервера и подключение к интернету."; read -r -p "Нажми Enter для выхода..."' ERR
cd "$(dirname "$0")"
ROOT_DIR="$PWD"
if [ ! -s "$ROOT_DIR/server-address.txt" ]; then
  echo "Впиши актуальный адрес сервера, который сообщил владелец (например, bore.pub:12345):"
  read -r SERVER_ADDRESS
  printf '%s\n' "$SERVER_ADDRESS" > "$ROOT_DIR/server-address.txt"
fi
case "$(uname -m)" in
  arm64) ARCH=arm64; URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jre_aarch64_mac_hotspot_21.0.13_9.tar.gz"; SUM="225bab0a09491ef06835488cd942f5d2befa9a0410a2484f0c8bbcf7506ec09a";;
  x86_64) ARCH=x64; URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jre_x64_mac_hotspot_21.0.13_9.tar.gz"; SUM="c909674b1c10c261b9a3fb7e9c0efebd303e33f88a4fe84be7135b5e2d711f89";;
  *) echo "Неподдерживаемый процессор."; read -r; exit 1;;
esac
JAVA="$ROOT_DIR/runtime/$ARCH/Contents/Home/bin/java"
if [ ! -x "$JAVA" ]; then
  echo "Первый запуск: загрузка Java 21 (~50 МБ)..."
  mkdir -p "$ROOT_DIR/runtime"
  TMPDIR_AOC="$(mktemp -d "$ROOT_DIR/runtime/install.XXXXXX")"
  trap 'rm -rf "$TMPDIR_AOC"' EXIT
  curl --fail --location --retry 3 --output "$TMPDIR_AOC/java.tar.gz" "$URL"
  ACTUAL="$(shasum -a 256 "$TMPDIR_AOC/java.tar.gz" | cut -d ' ' -f 1)"
  if [ "$ACTUAL" != "$SUM" ]; then echo "Ошибка проверки Java; установка отменена."; read -r; exit 1; fi
  mkdir -p "$TMPDIR_AOC/unpacked"
  tar -xzf "$TMPDIR_AOC/java.tar.gz" -C "$TMPDIR_AOC/unpacked" --strip-components 1
  test -x "$TMPDIR_AOC/unpacked/Contents/Home/bin/java"
  mv "$TMPDIR_AOC/unpacked" "$ROOT_DIR/runtime/$ARCH"
fi
export HMCL_USER_HOME="$ROOT_DIR/hmcl-home"
export HMCL_LOCAL_HOME="$ROOT_DIR/.hmcl"
"$JAVA" -cp "$ROOT_DIR/AeronauticsSetup.jar:$ROOT_DIR/HMCL.jar" AeronauticsSetup "$ROOT_DIR"
exec "$JAVA" -Dhmcl.offline.auth.restricted=false -jar "$ROOT_DIR/HMCL.jar"
