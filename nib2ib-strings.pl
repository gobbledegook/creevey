#!/usr/bin/perl

# note that you'll now need to have a separate strings file for each nib file,
# vs before where you could put them all in the same place.
# so far I've only made the MainMenu strings. which is not obvious from the file naming. oops.

my ($code) = @ARGV;
die "no country code!" unless $code;

open SRC, "<:encoding(utf16)", "ib-en.strings";
open OLD, "<:encoding(utf16)", "nib-$code.strings";
open NEW, ">:encoding(utf16)", "ib-$code.strings";

while (<OLD>) {
	($k, $v) = /^"([^"]*)"\s*=\s*"([^"]*)";$/;
	next unless $v;
	$dic{$k} = $v;
}

while (<SRC>) {
	s/= "([^"]*)";$/'= "' . ($dic{$1} || $1) . '";'/e;
	print NEW;
}
