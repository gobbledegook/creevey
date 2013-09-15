#!/usr/bin/perl
my %strings = qw/es Spanish tw zh_tw de German fr French it Italian/;

my ($code) = @ARGV;
die "no country code!" unless $code;

my @nibs = qw/MainMenu DYJpegtranPanel CreeveyWindow/;

for my $nib (@nibs) {
	system "rm -rf $strings{$code}.lproj/o$nib.nib";
	system "cp -Rf $strings{$code}.lproj/$nib.nib $strings{$code}.lproj/o$nib.nib";
	system "nibtool -v -W $strings{$code}.lproj/$nib.nib -I $strings{$code}.lproj/o$nib.nib -p English.lproj/p$nib.nib -d nib-$code.strings English.lproj/$nib.nib"
}

# incremental, only if previous localized version is different:
# -I $strings{$code}.lproj/o$nib.nib

# when using -I, the previous unlocalized file to compare with
# (best to copy from the previous release)
# -p English.lproj/p$nib.nib 

# write to file: -W

#system "open $strings{$code}.lproj";