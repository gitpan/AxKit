Name: AxKit
Version: 1.5.1
Release: 1
Copyright: Artistic or GPL (copyright AxKit.com Ltd)
Group: System Environment/Daemons
Source: http://axkit.org/download/%{name}-%{version}.tar.gz
BuildRoot: /tmp/%{name}-buildroot
Summary: AxKit - An XML Application Server for mod_perl
Requires: perl = 5.00503, mod_perl >= 1.25, perl-Error, perl-Digest-MD5, perl-Compress-Zlib

%description
AxKit is an XML Application Server for Apache. It provides on-the-fly
conversion from XML to any format, such as HTML, WAP or text using
either W3C standard techniques, or flexible custom code. AxKit also
uses a built-in Perl interpreter to provide some amazingly powerful
techniques for XML transformation. 

AxKit requires mod_perl.

%prep
%setup

%build
perl Makefile.PL
make
make test

%install
rm -rf $RPM_BUILD_ROOT
install -d $RPM_BUILD_ROOT/usr/lib/perl5/5.00503/i386-linux
make PREFIX=$RPM_BUILD_ROOT/usr INSTALLMAN3DIR=$RPM_BUILD_ROOT/usr/man/man3 install
rm -f $RPM_BUILD_ROOT/usr/lib/perl5/5.00503/i386-linux/perllocal.pod

%clean
rm -rf $RPM_BUILD_ROOT

%files
/usr/lib/perl5
/usr/man/man3
%doc README SUPPORT INSTALL Changes CONTRIB

%changelog
