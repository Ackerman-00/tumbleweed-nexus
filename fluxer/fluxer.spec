%global appid app.fluxer.Fluxer
%global debug_package %{nil}
# Prevent RPM from trying to auto-generate dependencies from the bundled Electron libraries
%global __requires_exclude_from ^%{_libdir}/%{name}/.*$
%global __provides_exclude_from ^%{_libdir}/%{name}/.*$
Name:           fluxer
Version:        2026.906.142314
Release:        0
Summary:        Free and open source instant messaging and VoIP platform
License:        AGPL-3.0-or-later AND BSD
Group:          Productivity/Networking/Talk/Clients
URL:            https://fluxer.app
Source0:        fluxer.rpm
Source1:        fluxer-rpmlintrc
BuildRequires:  cpio
BuildRequires:  hicolor-icon-theme
# Runtime dependencies for the bundled Electron/Chromium runtime
Requires:       at-spi2-core
Requires:       hicolor-icon-theme
Requires:       libX11.so.6()(64bit)
Requires:       libXcomposite.so.1()(64bit)
Requires:       libXdamage.so.1()(64bit)
Requires:       libXext.so.6()(64bit)
Requires:       libXfixes.so.3()(64bit)
Requires:       libXrandr.so.2()(64bit)
Requires:       libXss.so.1()(64bit)
Requires:       libXtst6
Requires:       libasound.so.2()(64bit)
Requires:       libatk-1.0.so.0()(64bit)
Requires:       libatk-bridge-2.0.so.0()(64bit)
Requires:       libatspi.so.0()(64bit)
Requires:       libcairo.so.2()(64bit)
Requires:       libcups.so.2()(64bit)
Requires:       libdbus-1.so.3()(64bit)
Requires:       libexpat.so.1()(64bit)
Requires:       libgbm.so.1()(64bit)
Requires:       libgio-2.0.so.0()(64bit)
Requires:       libglib-2.0.so.0()(64bit)
Requires:       libgobject-2.0.so.0()(64bit)
Requires:       libgtk-3.so.0()(64bit)
Requires:       libnotify.so.4()(64bit)
Requires:       libnspr4.so()(64bit)
Requires:       libnss3.so()(64bit)
Requires:       libnssutil3.so()(64bit)
Requires:       libpango-1.0.so.0()(64bit)
Requires:       libsmime3.so()(64bit)
Requires:       libudev.so.1()(64bit)
Requires:       libuuid1
Requires:       libxcb.so.1()(64bit)
Requires:       libxkbcommon.so.0()(64bit)
Requires:       xdg-utils
ExclusiveArch:  x86_64

%description
Fluxer is a free and open source instant messaging and VoIP platform built for
friends, groups, and communities. Self-hosting and more.

%prep
%setup -q -c -T
rpm2cpio %{SOURCE0} | cpio -idmv

%build
# No compilation required

%install

# 1. Install main app — handle both stable (opt/Fluxer) and canary (opt/Fluxer Canary) layouts
install -d -m 0755 %{buildroot}%{_libdir}/%{name}
FLUXER_SRC=$(ls -d opt/Fluxer* 2>/dev/null | head -n1)
if [ -z "$FLUXER_SRC" ]; then echo "No Fluxer source dir found in RPM"; exit 1; fi
cp -a "$FLUXER_SRC"/* %{buildroot}%{_libdir}/%{name}/
# Ensure wrapper target exists: stable binary is 'fluxer', canary is 'fluxer-canary'
if [ ! -x "%{buildroot}%{_libdir}/%{name}/%{name}" ] && [ -x "%{buildroot}%{_libdir}/%{name}/%{name}-canary" ]; then
    ln -sf %{name}-canary %{buildroot}%{_libdir}/%{name}/%{name}
fi
if [ ! -x "%{buildroot}%{_libdir}/%{name}/fluxer" ] && ls %{buildroot}%{_libdir}/%{name}/fluxer* >/dev/null 2>&1; then
    FIRST_BIN=$(ls %{buildroot}%{_libdir}/%{name}/fluxer* | head -n1)
    ln -sf $(basename "$FIRST_BIN") %{buildroot}%{_libdir}/%{name}/fluxer 2>/dev/null || true
fi

# 2. Launcher wrapper
install -d -m 0755 %{buildroot}%{_bindir}
cat > %{buildroot}%{_bindir}/%{name} <<'EOF'
#!/bin/sh
exec %{_libdir}/%{name}/%{name} "$@"
EOF
chmod 0755 %{buildroot}%{_bindir}/%{name}

# 3. Desktop file — handle fluxer.desktop or fluxer-canary.desktop
DESKTOP_SRC=$(ls usr/share/applications/fluxer*.desktop 2>/dev/null | head -n1)
if [ -z "$DESKTOP_SRC" ]; then echo "No desktop file found"; exit 1; fi
install -Dm0644 "$DESKTOP_SRC" \
    %{buildroot}%{_datadir}/applications/%{appid}.desktop

# Fix Exec= and Icon= for our relocation
sed -i 's|^Exec=.*|Exec=%{_bindir}/%{name} %U|' \
    %{buildroot}%{_datadir}/applications/%{appid}.desktop
sed -i 's|^Icon=.*|Icon=%{appid}|' \
    %{buildroot}%{_datadir}/applications/%{appid}.desktop

# 4. Icons — handle fluxer.png or fluxer-canary.png
for iconpath in usr/share/icons/hicolor/*/apps/fluxer*.png; do
    [ -e "$iconpath" ] || continue
    size=$(echo "$iconpath" | cut -d/ -f5)
    install -Dm0644 "$iconpath" \
        %{buildroot}%{_datadir}/icons/hicolor/${size}/apps/%{appid}.png
done

%files
%license %{_libdir}/%{name}/LICENSE.electron.txt
%doc %{_libdir}/%{name}/LICENSES.chromium.html
%{_bindir}/%{name}
%exclude %{_libdir}/%{name}/LICENSE.electron.txt
%exclude %{_libdir}/%{name}/LICENSES.chromium.html
%{_libdir}/%{name}/
%{_datadir}/applications/%{appid}.desktop
%dir %{_datadir}/icons/hicolor
%dir %{_datadir}/icons/hicolor/*
%dir %{_datadir}/icons/hicolor/*/apps
%{_datadir}/icons/hicolor/*/apps/%{appid}.png

%changelog
