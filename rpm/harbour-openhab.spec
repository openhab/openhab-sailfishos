Name:       harbour-openhab

Summary:    openHAB client for Sailfish OS
Version:    0.1
Release:    2
License:    EPL-2.0
URL:        www.openhab.org
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires: qt5-qtwebsockets
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  desktop-file-utils
BuildRequires:  pkgconfig(Qt5WebSockets)
BuildRequires: pkgconfig(qt5embedwidget)
BuildRequires:  pkgconfig(Qt5Test)
Requires: sailfish-components-webview-qt5

%description
This app is a native client for openHAB which allows easy access to your sitemaps. The documentation is available at www.openhab.org/docs/.


%prep
%setup -q -n %{name}-%{version}

%build

%qmake5 

%make_build


%install
%qmake5_install


desktop-file-install --delete-original         --dir %{buildroot}%{_datadir}/applications                %{buildroot}%{_datadir}/applications/*.desktop

%check
# ── Run automated tests (also executed by sfdk build) ──
export QT_QPA_PLATFORM=offscreen
export HOME=%{_builddir}

# ── Locate the source tree ──
# 1) Standard rpmbuild (GitHub Actions): source extracted to %{_builddir}/%{name}-%{version}
# 2) CWD already contains tests/ (in-tree build)
# 3) sfdk shadow build: extract project root from qmake-generated Makefile
SRCDIR=""
if [ -d "%{_builddir}/%{name}-%{version}/tests" ]; then
    SRCDIR="%{_builddir}/%{name}-%{version}"
elif [ -d tests ]; then
    SRCDIR="$(pwd)"
elif [ -f Makefile ]; then
    _pro=$(grep -oE '[^ ]+harbour-openhab\.pro' Makefile | head -1)
    [ -n "$_pro" ] && SRCDIR=$(dirname "$_pro")
fi

if [ -z "$SRCDIR" ] || [ ! -d "$SRCDIR/tests" ]; then
    echo "ERROR: tests/ directory not found"
    echo "  CWD:       $(pwd)"
    echo "  _builddir: %{_builddir}"
    echo "  tried:     $SRCDIR"
    ls -la
    exit 1
fi

cd "$SRCDIR"
echo "── Source directory: $(pwd) ──"

echo "── Building & running C++ unit tests ──"
pushd tests/unittest
%qmake5
%make_build
./tst_ssemanager || exit 1
popd

echo "── Building & running QML / JS tests ──"
pushd tests/qmltest
%qmake5
%make_build
./tst_qml || exit 1
popd

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png


