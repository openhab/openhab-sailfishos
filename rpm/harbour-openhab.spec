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
# Works for: standard rpmbuild, sfdk in-tree, and sfdk shadow builds
export QT_QPA_PLATFORM=offscreen
export HOME=%{_builddir}

# ── Locate the source tree ──
# Priority: 1) extracted tarball  2) CWD  3) Makefile grep (shadow build)
SRCDIR=""
if [ -d "%{_builddir}/%{name}-%{version}/tests" ]; then
    SRCDIR="%{_builddir}/%{name}-%{version}"
elif [ -d tests ]; then
    SRCDIR="$(pwd)"
elif [ -f Makefile ]; then
    _pro=$(grep -m1 -oE '[^ ]+harbour-openhab\.pro' Makefile)
    if [ -n "$_pro" ]; then
        _dir=$(dirname "$_pro")
        # resolve to an absolute path (handles relative & absolute refs)
        SRCDIR=$(cd "$_dir" 2>/dev/null && pwd)
    fi
fi

if [ -z "$SRCDIR" ] || [ ! -d "$SRCDIR/tests" ]; then
    echo "ERROR: tests/ directory not found – failing build"
    echo "  CWD:       $(pwd)"
    echo "  _builddir: %{_builddir}"
    echo "  tried:     $SRCDIR"
    exit 1
fi

echo "── Source directory: $SRCDIR ──"

# Build & run tests in dedicated out-of-tree directories under %%{_builddir}
# so generated files (Makefiles, .o, binaries) never pollute the source tree.
# Using qmake directly (not %%qmake5 macro) with an explicit .pro path avoids
# the path-concatenation issue that the macro can cause in shadow builds.

# Resolve the REAL qmake binary, bypassing the mb2 wrapper.
# The mb2 wrapper (in ~/.mb2/wrappers/) prepends the project root to the CWD
# which breaks sub-project builds.  The wrapper itself calls /usr/bin/qmake.
QMAKE=""
for _qm in /usr/bin/qmake /usr/lib/qt5/bin/qmake; do
    if [ -x "$_qm" ]; then
        QMAKE="$_qm"
        break
    fi
done
if [ -z "$QMAKE" ]; then
    echo "ERROR: qmake not found at /usr/bin/qmake or /usr/lib/qt5/bin/qmake"
    exit 1
fi
echo "── Using qmake: $QMAKE ──"

# Cross-compilation check: the sfdk build engine is x86 – ARM binaries
# (aarch64, armv7hl) cannot be executed there.  We still *compile* the tests
# to verify the code builds, but only *run* them for the native i486 target.
_can_execute=1
case "%{_arch}" in
    i?86|x86_64) ;;
    *)
        _can_execute=0
        echo "── Cross-compiling for %{_arch} – tests will be compiled but not executed ──"
        ;;
esac

echo "── Building C++ unit tests (out-of-tree) ──"
UNITTEST_BUILDDIR="%{_builddir}/test-build-unittest"
mkdir -p "$UNITTEST_BUILDDIR"
cd "$UNITTEST_BUILDDIR"
"$QMAKE" "$SRCDIR/tests/unittest/unittest.pro"
make %{?_smp_mflags}
if [ "$_can_execute" -eq 1 ]; then
    echo "── Running tst_ssemanager ──"
    ./tst_ssemanager || exit 1
else
    echo "── Skipping tst_ssemanager execution (cross-compiled for %{_arch}) ──"
fi

echo "── Building QML / JS tests (out-of-tree) ──"
QMLTEST_BUILDDIR="%{_builddir}/test-build-qmltest"
mkdir -p "$QMLTEST_BUILDDIR"
cd "$QMLTEST_BUILDDIR"
"$QMAKE" "$SRCDIR/tests/qmltest/qmltest.pro"
make %{?_smp_mflags}
if [ "$_can_execute" -eq 1 ]; then
    echo "── Running tst_qml ──"
    ./tst_qml || exit 1
else
    echo "── Skipping tst_qml execution (cross-compiled for %{_arch}) ──"
fi

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png


