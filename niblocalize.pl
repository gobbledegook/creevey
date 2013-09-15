#!/usr/bin/perl
my %strings = qw/es Spanish tw zh_tw de German fr French it Italian/;

my ($code) = @ARGV;
die "no country code!" unless $code;

my @nibs = qw/MainMenu/;# DYJpegtranPanel CreeveyWindow/;

for my $nib (@nibs) {
	system "rm -rf $strings{$code}.lproj/o$nib.nib";
	system "cp -Rf $strings{$code}.lproj/$nib.nib $strings{$code}.lproj/o$nib.nib";
	system "ibtool --write $strings{$code}.lproj/$nib.nib --incremental-file $strings{$code}.lproj/o$nib.nib --previous-file English.lproj/p$nib.nib --localize-incremental  --strings-file ib-$code.strings English.lproj/$nib.nib"
}

#--strings-file nib-$code.strings # breaks in ibtool!!!

# incremental, only if previous localized version is different:
# -I $strings{$code}.lproj/o$nib.nib

# when using -I, the previous unlocalized file to compare with
# (best to copy from the previous release)
# -p English.lproj/p$nib.nib 

# write to file: -W

#system "open $strings{$code}.lproj";