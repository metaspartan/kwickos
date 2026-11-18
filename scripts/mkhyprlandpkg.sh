#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; SRC=${SRC:-/src}; OUT=${OUT:-/out}
VER=$(tr -d '\r\n' < "$SRC/VERSION")
HYPRLAND=${HYPRLAND_VERSION:-v0.49.0}
HYPRPLUGINS=${HYPRLAND_PLUGINS_VERSION:-v0.49.0}
HYPRUTILS=${HYPRUTILS_VERSION:-v0.8.0}
HYPRLANG=${HYPRLANG_VERSION:-v0.6.3}
HYPRCURSOR=${HYPRCURSOR_VERSION:-v0.1.12}
HYPRGRAPHICS=${HYPRGRAPHICS_VERSION:-v0.1.3}
AQUAMARINE=${AQUAMARINE_VERSION:-v0.8.0}
SCANNER=${HYPRWAYLAND_SCANNER_VERSION:-v0.4.4}
PROTOCOLS=${HYPRLAND_PROTOCOLS_VERSION:-v0.6.4}
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl git cmake ninja-build meson pkg-config gcc g++ make xz-utils \
  libwayland-dev wayland-protocols libpixman-1-dev libdrm-dev libinput-dev libseat-dev libudev-dev libxkbcommon-dev \
  libegl-dev libgles-dev libgbm-dev libcairo2-dev libpango1.0-dev libpugixml-dev libzip-dev librsvg2-dev libtomlplusplus-dev \
  libjpeg-dev libwebp-dev libpng-dev libmagic-dev libre2-dev libxcb1-dev libxcb-composite0-dev libxcb-ewmh-dev libxcb-icccm4-dev \
  libxcb-render-util0-dev libxcb-res0-dev libxcb-xfixes0-dev libxcb-errors-dev libxcb-util-dev libxcursor-dev libxkbcommon-x11-dev \
  libdisplay-info-dev hwdata libliftoff-dev libgl-dev libopengl-dev libuuid1 uuid-dev libxcb-present-dev libxcb-dri3-dev libxcb-shm0-dev libxcb-render0-dev libxcb-xinput-dev \
  libspng-dev libsystemd-dev
W=$(mktemp -d); STAGE=$W/stage; mkdir -p "$STAGE"; cd "$W"
build() {
  local name=$1 repo=$2 tag=$3; shift 3
  git clone -q --depth 1 --branch "$tag" "https://github.com/hyprwm/$repo.git" "$name"
  cmake -S "$name" -B "$name/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr "$@"
  cmake --build "$name/build" -j8
  DESTDIR=$STAGE cmake --install "$name/build"
  DESTDIR= cmake --install "$name/build"
}
build hyprwayland-scanner hyprwayland-scanner "$SCANNER"
git clone -q --depth 1 --branch "$PROTOCOLS" https://github.com/hyprwm/hyprland-protocols.git hyprland-protocols
meson setup hyprland-protocols/build hyprland-protocols --prefix=/usr
DESTDIR=$STAGE meson install -C hyprland-protocols/build
meson install -C hyprland-protocols/build
build hyprutils hyprutils "$HYPRUTILS"
build hyprlang hyprlang "$HYPRLANG"
build hyprgraphics hyprgraphics "$HYPRGRAPHICS"
build hyprcursor hyprcursor "$HYPRCURSOR"
build aquamarine aquamarine "$AQUAMARINE"
mkdir hyprland-src && curl -fsSL "https://github.com/hyprwm/Hyprland/releases/download/$HYPRLAND/source-$HYPRLAND.tar.gz" | tar xz -C hyprland-src --strip-components=1
cd hyprland-src
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DNO_SYSTEMD=ON -DNO_UWSM=ON -DNO_HYPRPM=ON
cmake --build build -j8
DESTDIR=$STAGE cmake --install build
cmake --install build
cd "$W"
git clone -q --depth 1 --branch "$HYPRPLUGINS" https://github.com/hyprwm/hyprland-plugins.git hyprland-plugins
git -C hyprland-plugins apply <<'PATCH'
diff --git a/hyprbars/barDeco.cpp b/hyprbars/barDeco.cpp
index 6c7d906..dbdec28 100644
--- a/hyprbars/barDeco.cpp
+++ b/hyprbars/barDeco.cpp
@@ -234,6 +234,42 @@ void CHyprBar::renderText(SP<CTexture> out, const std::string& text, const CHypr
     cairo_paint(CAIRO);
     cairo_restore(CAIRO);
 
+    const bool GLYPHCLOSE = text == "\u2715", GLYPHMAX = text == "\u2610", GLYPHMIN = text == "\u2500";
+    if (GLYPHCLOSE || GLYPHMAX || GLYPHMIN) {
+        const double px = std::max(1.0, std::round((double)scale));
+        const double s  = std::round(10.0 * scale);
+        const double x0 = std::round((bufferSize.x - s) / 2.0);
+        const double y0 = std::round((bufferSize.y - s) / 2.0);
+        cairo_set_source_rgba(CAIRO, color.r, color.g, color.b, color.a);
+        cairo_set_line_width(CAIRO, px);
+        if (GLYPHCLOSE) {
+            const double h = px * M_SQRT1_2;
+            cairo_move_to(CAIRO, x0, y0 + h);
+            cairo_line_to(CAIRO, x0 + h, y0);
+            cairo_line_to(CAIRO, x0 + s, y0 + s - h);
+            cairo_line_to(CAIRO, x0 + s - h, y0 + s);
+            cairo_close_path(CAIRO);
+            cairo_fill(CAIRO);
+            cairo_move_to(CAIRO, x0 + s, y0 + h);
+            cairo_line_to(CAIRO, x0 + s - h, y0);
+            cairo_line_to(CAIRO, x0, y0 + s - h);
+            cairo_line_to(CAIRO, x0 + h, y0 + s);
+            cairo_close_path(CAIRO);
+            cairo_fill(CAIRO);
+        } else if (GLYPHMAX) {
+            const double l = x0 + px / 2.0, t = y0 + px / 2.0, r = x0 + s - px / 2.0, b = y0 + s - px / 2.0, rad = px;
+            cairo_new_sub_path(CAIRO);
+            cairo_arc(CAIRO, r - rad, t + rad, rad, -M_PI / 2.0, 0);
+            cairo_arc(CAIRO, r - rad, b - rad, rad, 0, M_PI / 2.0);
+            cairo_arc(CAIRO, l + rad, b - rad, rad, M_PI / 2.0, M_PI);
+            cairo_arc(CAIRO, l + rad, t + rad, rad, M_PI, 3.0 * M_PI / 2.0);
+            cairo_close_path(CAIRO);
+            cairo_stroke(CAIRO);
+        } else {
+            cairo_rectangle(CAIRO, x0, y0 + std::round(s / 2.0), s, px);
+            cairo_fill(CAIRO);
+        }
+    } else {
     // draw title using Pango
     PangoLayout* layout = pango_cairo_create_layout(CAIRO);
     pango_layout_set_text(layout, text.c_str(), -1);
@@ -263,6 +299,7 @@ void CHyprBar::renderText(SP<CTexture> out, const std::string& text, const CHypr
     pango_cairo_show_layout(CAIRO, layout);
 
     g_object_unref(layout);
+    }
 
     cairo_surface_flush(CAIROSURFACE);
 
@@ -583,6 +620,38 @@ void CHyprBar::renderPass(PHLMONITOR pMonitor, const float& a) {
         glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
     }
 
+    static auto* const PPARTOFWINDOW = (Hyprlang::INT* const*)HyprlandAPI::getConfigValue(PHANDLE, "plugin:hyprbars:bar_part_of_window")->getDataStaticPtr();
+    if (ROUNDING && **PPARTOFWINDOW && PWINDOW->m_wlSurface && !PWINDOW->m_wlSurface->small()) {
+        const auto SURFACE = PWINDOW->m_wlSurface->resource();
+        if (SURFACE && SURFACE->m_current.texture) {
+            CBox contentBox = {PWINDOW->m_realPosition->value().x + PWINDOW->m_floatingOffset.x - pMonitor->m_position.x,
+                               PWINDOW->m_realPosition->value().y + PWINDOW->m_floatingOffset.y - pMonitor->m_position.y, PWINDOW->m_realSize->value().x,
+                               PWINDOW->m_realSize->value().y};
+            contentBox.translate(WORKSPACEOFFSET);
+            const auto UNSCALED = contentBox.size();
+            contentBox.scale(pMonitor->m_scale).round();
+            CRegion band = CRegion(CBox{contentBox.x, contentBox.y, contentBox.w, std::ceil(ROUNDING * pMonitor->m_scale) + 1});
+            CRegion damage = g_pHyprOpenGL->m_renderData.damage;
+            band.intersect(damage);
+            if (!band.empty()) {
+                const auto OLDCLIPBOX    = g_pHyprOpenGL->m_renderData.clipBox;
+                CRegion    OLDCLIPREGION = g_pHyprOpenGL->m_renderData.clipRegion;
+                g_pHyprOpenGL->m_renderData.clipBox    = {};
+                g_pHyprOpenGL->m_renderData.clipRegion = band;
+                g_pHyprOpenGL->m_renderData.currentWindow = PWINDOW;
+                g_pHyprOpenGL->m_renderData.surface       = SURFACE;
+                g_pHyprRenderer->calculateUVForSurface(PWINDOW, SURFACE, pMonitor, true, contentBox.size(), UNSCALED, false);
+                g_pHyprOpenGL->renderTexture(SURFACE->m_current.texture, contentBox, a * PWINDOW->m_activeInactiveAlpha->value(), 0, 2.0f, false, true);
+                g_pHyprOpenGL->m_renderData.currentWindow.reset();
+                g_pHyprOpenGL->m_renderData.surface.reset();
+                g_pHyprOpenGL->m_renderData.primarySurfaceUVTopLeft     = Vector2D(-1, -1);
+                g_pHyprOpenGL->m_renderData.primarySurfaceUVBottomRight = Vector2D(-1, -1);
+                g_pHyprOpenGL->m_renderData.clipBox                     = OLDCLIPBOX;
+                g_pHyprOpenGL->m_renderData.clipRegion                  = OLDCLIPREGION;
+            }
+        }
+    }
+
     if (SHOULDBLUR)
         g_pHyprOpenGL->renderRectWithBlur(titleBarBox, color, scaledRounding, m_pWindow->roundingPower(), a);
     else
PATCH
if [ -f hyprland-plugins/hyprbars/CMakeLists.txt ]; then
  cmake -S hyprland-plugins/hyprbars -B hyprland-plugins/hyprbars/build -G Ninja -DCMAKE_BUILD_TYPE=Release
  cmake --build hyprland-plugins/hyprbars/build -j8
  BARS=$(ls hyprland-plugins/hyprbars/build/*hyprbars.so)
else
  make -C hyprland-plugins/hyprbars all
  BARS=$(ls hyprland-plugins/hyprbars/*hyprbars.so)
fi
mkdir -p "$STAGE/usr/lib/kwick/hypr"
cp "$BARS" "$STAGE/usr/lib/kwick/hypr/hyprbars.so"
rm -rf "$STAGE/usr/include" "$STAGE/usr/lib/"*/pkgconfig "$STAGE/usr/lib/"*/cmake "$STAGE/usr/share/pkgconfig" "$STAGE/usr/lib/"*/*.a
find "$STAGE/usr/bin" "$STAGE/usr/lib" -type f \( -perm -u+x -o -name '*.so*' \) -exec strip --strip-unneeded {} + 2>/dev/null || true
apt-get install -y --no-install-recommends dpkg-dev >/dev/null
mkdir -p debian && echo "Source: kwick-hyprland" > debian/control
LIBDIR=$(ls -d "$STAGE"/usr/lib/*-linux-gnu)
deps=$(dpkg-shlibdeps -O --ignore-missing-info -l"$LIBDIR" -xkwick-hyprland "$STAGE/usr/bin/Hyprland" "$STAGE/usr/bin/hyprctl" "$STAGE/usr/bin/hyprcursor-util" 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
P=$W/pkg; mkdir -p "$P/DEBIAN"; cp -a "$STAGE/usr" "$P/usr"
cat > "$P/DEBIAN/control" <<EOF
Package: kwick-hyprland
Version: $VER
Architecture: $ARCH
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: x11
Priority: optional
Depends: $deps, xwayland, libseat1, libdisplay-info2, libliftoff0, libjpeg62-turbo, libwebp7, libpng16-16t64, librsvg2-2, libmagic1t64, libspng0, libtomlplusplus3t64
Description: Hyprland $HYPRLAND tiling Wayland compositor for KwickOS
 Hyprland and its hypr* libraries (hyprutils, hyprlang, hyprgraphics, hyprcursor,
 aquamarine) built from pinned upstream source for Debian 13, installed under /usr.
EOF
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-hyprland_${VER}_${ARCH}.deb" >/dev/null
echo "packaged kwick-hyprland $VER (Hyprland $HYPRLAND)"
