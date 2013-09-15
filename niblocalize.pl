#!/usr/bin/perl
my %strings = qw/es Spanish tw zh_tw de German/;

my ($code) = @ARGV;
die "no country code!" unless $code;

my @nibs = qw/MainMenu DYJpegtranPanel CreeveyWindow/;

for my $nib (@nibs) {
	system "rm -rf $strings{$code}.lproj/o$nib.nib";
	system "cp -Rf $strings{$code}.lproj/$nib.nib $strings{$code}.lproj/o$nib.nib";
	system "nibtool -v -I $strings{$code}.lproj/o$nib.nib -W $strings{$code}.lproj/$nib.nib -d nib-$code.strings English.lproj/$nib.nib"
}

#system "open $strings{$code}.lproj";