Name:       harbour-openhab

Summary:    openHAB client for Sailfish OS
Version:    0.1
Release:    1
License:    LICENSE
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

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png


