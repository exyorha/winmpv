#!/bin/sh

set -e

harfbuzz_version=8.3.1
freetype_version=2.13.2
fribidi_version=1.0.13
ffmpeg_version=6.1.1
libplacebo_version=v6.338.2
libass_version=0.17.1
mpv_version=0.37.0

download_and_unpack_windows_dependency() {
    local url="$1"
    local basename="$(basename -- "$url")"
    local stem

    if [ -z "$2" ]; then
        stem="$(basename -s ".7z" -- "$(basename -s ".tar.xz" "$(basename -s ".tar.gz" -- "$url")")")"
    else
        stem="$2"
    fi

    echo "$url" "$basename" "$stem"

    if [ ! -d "windows-build-deps/${stem}" ]; then
        if [ ! -f "dl/${basename}" ]; then
            wget -O "dl/${basename}.part" "${url}"
            mv "dl/${basename}.part" "dl/${basename}"
        fi

        mkdir -p windows-build-deps/part

        if [[ $basename = *.7z ]]; then
            7z -owindows-build-deps/part x "dl/${basename}"
        else
            tar xf "dl/${basename}" -C windows-build-deps/part
        fi
        mv "windows-build-deps/part/${stem}" "windows-build-deps"
    fi
}

build_meson_package() {
    local name="$1"
    local version="$2"
    shift 2

    mkdir -p "windows-build-deps/${name}-build"
    meson setup "$(realpath -- "windows-build-deps/${name}-build")" "$(realpath "windows-build-deps/${name}-${version}")" \
        --prefix "${winprefix}" --buildtype release --cross-file meson-mingw-cross.txt -Dprefer_static=true "$@"

    (cd "windows-build-deps/${name}-build" && meson install)
}

winprefix="$(realpath -- windows-build-root-path)"

mkdir -p "$(realpath -- dl)"
mkdir -p "${winprefix}/bin"

if [ ! -e "${winprefix}/bin/x86_64-w64-mingw32-pkg-config" ]; then
    cat > "${winprefix}/bin/x86_64-w64-mingw32-pkg-config" <<EOF
#!/bin/sh

export PKG_CONFIG_LIBDIR="${winprefix}/lib/pkgconfig"
exec pkgconf "\$@"
EOF

    chmod +x "${winprefix}/bin/x86_64-w64-mingw32-pkg-config"
fi

export PATH="${winprefix}/bin:${PATH}"

download_and_unpack_windows_dependency "https://github.com/harfbuzz/harfbuzz/releases/download/${harfbuzz_version}/harfbuzz-${harfbuzz_version}.tar.xz"
download_and_unpack_windows_dependency "https://download.savannah.gnu.org/releases/freetype/freetype-${freetype_version}.tar.xz"
download_and_unpack_windows_dependency "https://github.com/fribidi/fribidi/releases/download/v${fribidi_version}/fribidi-${fribidi_version}.tar.xz"
download_and_unpack_windows_dependency "https://ffmpeg.org/releases/ffmpeg-${ffmpeg_version}.tar.xz"

if [ ! -d "windows-build-deps/libplacebo-${libplacebo_version}" ]; then
    git clone --branch=${libplacebo_version} --depth=1 --recurse-submodules --shallow-submodules -- \
        https://code.videolan.org/videolan/libplacebo "windows-build-deps/libplacebo-${libplacebo_version}"
fi

download_and_unpack_windows_dependency "https://github.com/libass/libass/releases/download/${libass_version}/libass-${libass_version}.tar.xz"
download_and_unpack_windows_dependency "https://github.com/mpv-player/mpv/archive/refs/tags/v${mpv_version}.tar.gz" "mpv-${mpv_version}"

build_meson_package "harfbuzz" "${harfbuzz_version}" --default-library static -Dtests=disabled -Dutilities=disabled -Dfreetype=disabled

build_meson_package "freetype" "${freetype_version}" --default-library static -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=enabled \
    -Dpng=disabled -Dzlib=disabled

build_meson_package "fribidi" "${fribidi_version}" --default-library static -Dbin=false -Ddocs=false -Dtests=false

if [ ! -f "windows-build-deps/libass-build/config.status" ]; then
    mkdir -p "windows-build-deps/libass-build"
    (cd "windows-build-deps/libass-build" && "../libass-${libass_version}/configure" --build="$(cc -dumpmachine)" --host=x86_64-w64-mingw32 \
        --prefix="${winprefix}" --disable-shared --disable-fontconfig --enable-directwrite --disable-coretext --disable-libunibreak --with-pic)
fi

make -C "windows-build-deps/libass-build" -j8 install

meson setup "$(realpath -- "windows-build-deps/libplacebo-build")" "$(realpath -- "windows-build-deps/libplacebo-${libplacebo_version}")" \
    --prefix "${winprefix}" --buildtype release --cross-file meson-mingw-cross.txt --default-library static \
    -Dvulkan=disabled -Dopengl=enabled -Dd3d11=disabled -Dlcms=disabled -Ddovi=disabled -Ddemos=false \
    -Dunwind=disabled -Dxxhash=disabled -Dglslang=disabled -Dshaderc=disabled --reconfigure

(cd "windows-build-deps/libplacebo-build" && meson install)

if [ ! -f "windows-build-deps/ffmpeg-build/Makefile" ]; then
    echo "Configuring ffmpeg"

    mkdir -p "windows-build-deps/ffmpeg-build"
    (cd "windows-build-deps/ffmpeg-build" && "../ffmpeg-${ffmpeg_version}/configure" --prefix="${winprefix}" --disable-programs \
        --cross-prefix=x86_64-w64-mingw32- --arch=x86_64 --target-os=win32 --disable-doc --disable-avdevice --disable-postproc \
        --disable-network --disable-encoders --disable-muxers --enable-libfreetype --enable-libfribidi --disable-libharfbuzz \
        --pkg-config=x86_64-w64-mingw32-pkg-config)
fi

make -C "windows-build-deps/ffmpeg-build" -j8 install

meson setup "$(realpath -- "windows-build-deps/mpv-build")" "$(realpath -- "windows-build-deps/mpv-${mpv_version}")" \
    --prefix "${winprefix}" --default-library shared --buildtype release --cross-file meson-mingw-cross.txt -Dgpl=false \
    -Dcplayer=false -Dlibmpv=true -Dc_link_args="-static-libgcc -static-libstdc++ -Wl,-Bstatic -lstdc++" -Dstrip=true

(cd "windows-build-deps/mpv-build" && meson install)

(cd "${winprefix}" && tar cf ../windows-libmpv.tar bin/libmpv-2.dll include/mpv lib/pkgconfig/mpv.pc lib/libmpv.dll.a)
