# platform: macOS-only -- llvm-lipo builds the universal stand-in
#   usage: . tests/fixtures/tiny-stage.sh; mk_toolchain ARCH; tiny_machos DIR [VERSION]; tiny_stage STAGE MACHO
#          tiny_machos writes DIR/x86_64, DIR/arm64 (a bare Mach-O header of each arch, then VERSION as a
#          string, as GNU Make's binary carries its version) and DIR/fat (both).
#          tiny_stage lays out the tree build/build-make.sh stages, under STAGE/usr/local/mavergreen/make,
#          with MACHO as bin/make.
tiny_machos() {
  printf '\317\372\355\376\007\000\000\001\003\000\000\000\002\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000' > "$1/x86_64"
  printf '\317\372\355\376\014\000\000\001\000\000\000\000\002\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000' > "$1/arm64"
  if [ -n "${2:-}" ]; then printf '\000%s\000' "$2" | tee -a "$1/x86_64" >> "$1/arm64"; fi
  "$CLANG22_BIN/llvm-lipo" -create "$1/x86_64" "$1/arm64" -output "$1/fat"
  chmod +x "$1/x86_64" "$1/arm64" "$1/fat"
}

tiny_stage() {
  _ts="$1/usr/local/mavergreen/make"
  mkdir -p "$_ts/bin" "$_ts/include" "$_ts/share/man/man1" "$_ts/share/info" "$_ts/share/doc/make"
  cp "$2" "$_ts/bin/make"
  ln -s make "$_ts/bin/gmake"
  printf '/* gnumake.h */\n' > "$_ts/include/gnumake.h"
  printf '.TH MAKE 1\n' > "$_ts/share/man/man1/make.1"
  ln -s make.1 "$_ts/share/man/man1/gmake.1"
  printf 'make.info\n' > "$_ts/share/info/make.info"
  printf 'make.info-1\n' > "$_ts/share/info/make.info-1"
  printf 'GNU GENERAL PUBLIC LICENSE\n' > "$_ts/share/doc/make/COPYING"
}
