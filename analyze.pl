#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use File::Slurper qw/ read_binary /;
use Data::Dumper;

my $path = shift // die "file argument missing";

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

	$obj{data} = substr $data, $offset, $obj{length};
	$offset += $obj{length};
	push @{$file_data{objects}}, \%obj;

	last if $obj{sym} eq "END\0";
}

$file_data{close_tag} = substr $data, $offset, 0x9;
$offset += 0x9;

die "invalid close tag: $file_data{close_tag} at offset $offset" unless $file_data{close_tag} eq "</roblox>";
die "invalid close tag before end of file at offset $offset" unless $offset == length $data;


say Dumper \%file_data;



for my $obj (grep $_->{sym} eq 'INST', @{$file_data{objects}}) {
	my $data = $obj->{data};
	my %inst_data;
	my $offset = 0;
	
	@inst_data{qw/ i1 i2 name_length /} = unpack 'SLL', substr $data, $offset, 0xa;
	$offset += 0xa;

	$inst_data{name} = substr $data, $offset, $inst_data{name_length};
	$offset += $inst_data{name_length};

	@inst_data{qw/ i3 i4 /} = unpack 'LL', substr $data, $offset, 0x8;
	$offset += 0x8;
	# die "n1 not null: $inst_data{n1}" unless $inst_data{n1} == 0;

	say "$inst_data{name}";
	say "i have ", $obj->{length} - $offset, " length remaining: $obj->{length} - $offset : $inst_data{name_length}";
}






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