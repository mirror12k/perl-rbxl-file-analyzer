#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use File::Slurper qw/ read_binary /;
use Data::Dumper;







sub to_hex { join '', map sprintf ('%02x', ord $_), split '', shift }









my $path = shift // die "file argument missing";


# file data extraction
my $data = read_binary $path;
my %file_data;
my $offset = 0;

$file_data{signature} = substr $data, $offset, 0x10;
$offset += 0x10;
die "incorrect signature: $file_data{signature}" unless "<roblox!\x89\xFF\r\n\x1A\n\0\0" eq $file_data{signature};

@file_data{qw/ i1 i2 n1 n2 /} = unpack 'LLLL', substr $data, $offset, 0x10;
$offset += 0x10;

die "n1 not null: $file_data{n1}" unless $file_data{n1} == 0;
die "n2 not null: $file_data{n2}" unless $file_data{n2} == 0;
die "strange i2: $file_data{i1}, $file_data{i2}" unless $file_data{i1} + 2 == $file_data{i2};

$file_data{objects} = [];
while ($offset < length $data) {
	my %obj;
	$obj{sym} = substr $data, $offset, 0x4;
	$offset += 0x4;
	die "unknown sym: '$obj{sym}' at offset $offset" unless $obj{sym} eq 'INST' or $obj{sym} eq 'PROP' or $obj{sym} eq 'PRNT' or $obj{sym} eq "END\0";

	@obj{qw/ length i1 n1 /} = unpack "LLL", substr $data, $offset, 0xc;
	$offset += 0xc;
	die "n1 not null: $obj{n1} at offset $offset" unless $obj{n1} == 0;
	warn "strange i1: $obj{length}, $obj{i1} at offset $offset" unless $obj{length} - 2 == $obj{i1};

	die "end has non-null length: $obj{length} at offset $offset" unless $obj{sym} ne "END\0" or $obj{length} == 0;

	$obj{raw_data} = substr $data, $offset, $obj{length};
	$offset += $obj{length};
	push @{$file_data{objects}}, \%obj;

	last if $obj{sym} eq "END\0";
}

$file_data{close_tag} = substr $data, $offset, 0x9;
$offset += 0x9;

die "invalid close tag: $file_data{close_tag} at offset $offset" unless $file_data{close_tag} eq "</roblox>";
die "invalid close tag before end of file at offset $offset" unless $offset == length $data;



# INST data digesting
my %inst_ids;
for my $obj (grep $_->{sym} eq 'INST', @{$file_data{objects}}) {
	my $data = $obj->{raw_data};
	my %inst_data;
	my $offset = 0;
	
	my $typeflag = unpack 'C', substr $data, $offset, 1;
	if (($typeflag & 0xf0) == 0xf0) {
		$inst_data{flags} = substr $data, $offset, 2;
		$offset += 2;

		@inst_data{qw/ id name_length /} = unpack 'LL', substr $data, $offset, 8;
		$offset += 8;
	} elsif (($typeflag & 0xf0) == 0x40) {
		$inst_data{flags} = substr $data, $offset, 1;
		$offset += 1;

		my ($val) = unpack 'L', substr $data, $offset, 4;
		$offset += 8;
		@inst_data{qw/ id name_length /} = ($val, $val);
	} elsif (($typeflag & 0xf0) == 0xE0) {
		$inst_data{flags} = substr $data, $offset, 1;
		$offset += 1;

		@inst_data{qw/ id name_length /} = unpack 'LL', substr $data, $offset, 8;
		$offset += 8;
	} else {
		die "unknown typeflag: " . to_hex(chr $typeflag);
	}

	$inst_data{name} = substr $data, $offset, $inst_data{name_length};
	$offset += $inst_data{name_length};

	@inst_data{qw/ i3 i4 /} = unpack 'LL', substr $data, $offset, 0x8;
	$offset += 0x8;

	say to_hex ($inst_data{flags});
	# say join '', (unpack "b16", $inst_data{i1});
	say $obj->{length} - $offset, " remaining: $inst_data{id} : $inst_data{name_length} : '$inst_data{name}'";

	die "object id reused $inst_data{id}" if exists $inst_ids{$inst_data{id}};
	$inst_ids{$inst_data{id}} = $obj;
	$obj->{data} = \%inst_data;
}
$file_data{inst_by_id} = \%inst_ids;


say "-\n" x 3;

# prop data processing
for my $obj (grep $_->{sym} eq 'PROP', @{$file_data{objects}}) {
	my $data = $obj->{raw_data};
	my %prop_data;
	my $offset = 0;
	
	my $typeflag = unpack 'C', substr $data, $offset, 1;
	if (($typeflag & 0xf0) == 0xf0) {
		$prop_data{flags} = substr $data, $offset, 2;
		$offset += 2;

		@prop_data{qw/ id name_length /} = unpack 'LL', substr $data, $offset, 8;
		$offset += 8;
	} elsif (($typeflag & 0xf0) == 0x40) {
		$prop_data{flags} = substr $data, $offset, 1;
		$offset += 1;

		my ($val) = unpack 'L', substr $data, $offset, 4;
		$offset += 8;
		@prop_data{qw/ id name_length /} = ($val, $val);
	} elsif (($typeflag & 0xf0) == 0xE0) {
		$prop_data{flags} = substr $data, $offset, 1;
		$offset += 1;

		@prop_data{qw/ id name_length /} = unpack 'LL', substr $data, $offset, 8;
		$offset += 8;
		# typeflag 0xE does somethin really wierd with the value type
		# there's a Name string value which has 5 bytes as it's length with garbage data for some reason
	} else {
		# something really wierd with a 0xFF typeflag, does something strange to the value
		# it seems to add some junk-like data after the value
		die "unknown typeflag: " . to_hex(chr $typeflag);
	}

	$prop_data{name} = substr $data, $offset, $prop_data{name_length};
	$offset += $prop_data{name_length};

	$prop_data{value_type} = unpack 'C', substr $data, $offset, 1;
	$offset += 1;

	if ($prop_data{value_type} eq 1) {
		$prop_data{value_length} = unpack 'L', substr $data, $offset, 4;
		$offset += 4;

		$prop_data{value} = substr $data, $offset, $prop_data{value_length};
		$offset += $prop_data{value_length};
		# say "got string: $prop_data{value}";
	} elsif ($prop_data{value_type} eq 2) {
		$prop_data{value} = unpack 'C', substr $data, $offset, 1;
		$offset += 1;

		# say "got bool: $prop_data{value}";
	} elsif ($prop_data{value_type} eq 3) {
		$prop_data{value} = unpack 'L', substr $data, $offset, 4;
		$offset += 4;

		# say "got unknown value (supposed to be numerical, but doesn't look like one): $prop_data{value}";
	} elsif ($prop_data{value_type} eq 4) {
		$prop_data{value} = unpack 'L', substr $data, $offset, 4;
		$offset += 4;

		# say "got unknown value (some numerical?): $prop_data{value}";
	} elsif ($prop_data{value_type} eq 5) {
		$prop_data{value} = unpack 'd', substr $data, $offset, 8;
		$offset += 8;

		# say "got unknown value (assumed a double): $prop_data{value}";
	} elsif ($prop_data{value_type} eq 11) {
		$prop_data{value} = unpack 'L', substr $data, $offset, 4;
		$offset += 4;

		# say "got unknown value (color type): $prop_data{value}";
	} elsif ($prop_data{value_type} eq 12) {
		$prop_data{value} = [unpack 'LLL', substr $data, $offset, 12];
		$offset += 12;

		# say "got unknown value (color3 type?): ", Dumper $prop_data{value};
	} elsif ($prop_data{value_type} eq 14) {
		$prop_data{value} = [unpack 'LLL', substr $data, $offset, 12];
		$offset += 12;

		# say "got unknown value (vector3 type?): ", Dumper $prop_data{value};
	} elsif ($prop_data{value_type} eq 16) {
		$prop_data{cframe_type} = unpack 'C', substr $data, $offset, 1;
		$offset += 1;
		if ($prop_data{cframe_type} == 0) {
			# i don't know this format and unpacking 12 longs just doesn't make sense
			# probably has a set of floats somewhere in there
			$prop_data{value} = substr $data, $offset, 0x30;
			$offset += 0x30;
		} elsif ($prop_data{cframe_type} == 2) {
			$prop_data{value} = [unpack 'LLL', substr $data, $offset, 12];
			$offset += 12;
		} else {
			warn "unknown cframe_type: $prop_data{cframe_type}";
		}

		# say "got some cframe value (type $prop_data{cframe_type}): ", Dumper $prop_data{value};
	} elsif ($prop_data{value_type} eq 18) {
		$prop_data{value} = unpack 'L', substr $data, $offset, 4;
		$offset += 4;

		# say "got unknown value (enum type?): $prop_data{value}";
	} elsif ($prop_data{value_type} eq 19) {
		$prop_data{value} = unpack 'L', substr $data, $offset, 4;
		$offset += 4;

		# say "got unknown value (supposed to be a part pointer?): $prop_data{value}";
	} elsif ($prop_data{value_type} eq 25) {
		$prop_data{value} = unpack 'C', substr $data, $offset, 1;
		$offset += 1;

		# say "got unknown value (??? type?): $prop_data{value}";
	} else {
		warn "unknown property value type: $prop_data{value_type}";
	}

	# say to_hex ($prop_data{flags});
	say $obj->{length} - $offset, " remaining: $prop_data{value_type} : '$prop_data{name}'($prop_data{name_length}) : $prop_data{value}"
		; # if $obj->{length} != $offset;

	die "object id reused $prop_data{id}" unless exists $file_data{inst_by_id}{$prop_data{id}};
	push @{$file_data{inst_by_id}{$prop_data{id}}{properties}}, $obj;
	$obj->{data} = \%prop_data;
}



# say Dumper \%file_data;




# my %ids;
# for my $obj (@{$file_data{objects}}) {
# 	if ($obj->{sym} eq "INST") {
# 		if (exists $ids{$obj->{i1}}) {
# 			warn "$obj->{i1} already exists!";
# 		} else {
# 			$ids{$obj->{i1}} = $obj;
# 		}
# 	}
# }
# say join ',', sort keys %ids;

# all INST tags have some significant length
# say join ',', sort map $_->{length}, grep $_->{sym} eq "INST", @{$file_data{objects}};




# 3C726F626C6F782189FF0D0A1A0A0000