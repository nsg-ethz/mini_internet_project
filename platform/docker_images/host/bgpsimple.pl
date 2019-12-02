#!/usr/bin/perl

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation.
#
# The program is hosted at http://bgpsimple.googlecode.com
#
# Please mail any bugs, suggestions and feature requests to
# the.einval (at) googlemail.com

use strict;
use warnings;
use Getopt::Long;

use Net::BGP;
use Net::BGP::Process;

my $version = "v0.12";
my $version_date = "22-Jan-2011";

my $help = <<EOF;

bgp_simple.pl: Simple BGP peering and route injection script.
Version $version, $version_date.

usage:
bgp_simple.pl:
	       	-myas   	ASNUMBER	# (mandatory) our AS number
	       	-myip   	IP address	# (mandatory) our IP address to source the sesion from
	     	-peerip 	IP address	# (mandatory) peer IP address
		-peeras		ASNUMBER	# (mandatory) peer AS number
		[-holdtime]	Seconds		# (optional) BGP hold time duration in seconds (default 60s)
		[-keepalive]	Seconds		# (optional) BGP KeepAlive timer duration in seconds (default 20s)
		[-nolisten]			# (optional) dont listen at \$myip, tcp/179
 		[-v]                       	# (optional) provide verbose output to STDOUT, use twice to get debugs
 		[-p file]                       # (optional) prefixes to advertise (bgpdump formatted)
		[-o file]			# (optional) write all sent and received UPDATE messages to file
                [-m number]                     # (optional) maximum number of prefixes to advertise
                [-n IP address]                 # (optional) next hop self, overrides original value
		[-l number]			# (optional) set default value for LOCAL_PREF
                [-dry]                 		# (optional) dry run; dont build adjacency, but check prefix file (requires -p)
                [-f KEY=REGEX]                 	# (optional) filter on input prefixes (requires -p), repeat for multiple filters
							KEY is one of the following attributes (CaSE insensitive):

						 	NEIG		originating neighbor
							NLRI		NLRI/prefix(es)
 							ASPT		AS_PATH
							ORIG		ORIGIN
							NXHP		NEXT_HOP
							LOCP		LOCAL_PREF
							MED		MULTI_EXIT_DISC
							COMM		COMMUNITY
							ATOM		ATOMIC_AGGREGATE
							AGG		AGGREGATOR

							REGEX is a perl regular expression to be expected in a
							match statement (m/REGEX/)

Without any prefix file to import, only an adjacency is established and the received NLRIs, including their attributes, are logged.

EOF

my %BGP_ERROR_CODES = (
			1 => { 		__NAME__ => "Message Header Error",
				 	1 => "Connection Not Synchronized",
					2 => "Bad Message Length",
					3 => "Bad Message Type",
			},
			2 => {		__NAME__ => "OPEN Message Error",
					1 => "Unsupported Version Number",
					2 => "Bad Peer AS",
					3 => "Bad BGP Identifier",
					4 => "Unsupported Optional Parameter",
					5 => "[Deprecated], see RFC4271",
					6 => "Unacceptable Hold Time",
			},
			3 => { 		__NAME__ => "UPDATE Message Error",
					1 => "Malformed Attribute List",
					2 => "Unrecognized Well-known Attribute",
					3 => "Missing Well-known Attribute",
					4 => "Attribute Flags Error",
					5 => "Attribute Length Error",
					6 => "Invalid ORIGIN Attribute",
					7 => "[Deprecated], see RFC4271",
					8 => "Invalid NEXT_HOP Attribute",
					9 => "Optional Attribute Error",
					10 => "Invalid Network Field",
					11 => "Malformed AS_PATH",
			},
			4 => {		__NAME__ => "Hold Timer Expired",
			},
			5 => {		__NAME__ => "Finite State Machine Error",
			},
			6 => {		__NAME__ => "Cease",
					1 => "Maximum Number of Prefixes Reached",
					2 => "Administrative Shutdown",
					3 => "Peer De-configured",
					4 => "Administrative Reset",
					5 => "Connection Rejected",
					6 => "Other Configuration Change",
					7 => "Connection Collision Resolution",
					9 => "Out of Resources",
			},
);

my $infile;
my $outfile;
my $prefix_limit;
my $verbose = 0;
my $dry;
my $next_hop_self = "0";
my $adj_next_hop = 0;
my $default_local_pref = 0;
my $myas;
my $myip;
my $peeras;
my $peerip;
my %regex_filter;
my $holdtime = 60;
my $keepalive = 20;
my $nolisten = 0;

GetOptions( 	'help' 		=> sub{ sub_debug("m","$help"); exit; },
		'm=s' 		=> \$prefix_limit,
		'l=s' 		=> \$default_local_pref,
		'v+' 		=> \$verbose,
		'dry' 		=> \$dry,
		'n:s' 		=> \$next_hop_self,
		'p=s' 		=> \$infile,
		'f=s' 		=> \%regex_filter,
		'o=s' 		=> \$outfile,
		'myas=s' 	=> \$myas,
		'myip=s' 	=> \$myip,
		'peeras=s' 	=> \$peeras,
		'peerip=s' 	=> \$peerip,
		'holdtime=s'	=> \$holdtime,
		'keepalive=s'	=> \$keepalive,
		'nolisten'	=> \$nolisten
 );


die "\nPlease provide -myas, -myip, -peerip and -peeras!\n$help" unless ($myas && $myip && $peeras && $peerip);

die "Peer IP address is not valid: $peerip" 	if (sub_checkip($peerip));
die "Peer AS number is not valid: $peeras"   	if (sub_checkas($peeras));
die "Our IP address is not valid: $myip"   	if (sub_checkip($myip));
die "Our AS number is not valid: $myas"   	if (sub_checkas($myas));

my $peer_type = ( $myas == $peeras ) ? "iBGP" : "eBGP";

if ($next_hop_self ne "0")
{
	if ($peer_type eq "eBGP")
	{
		sub_debug ("i","Force to change next hop ignored due to eBGP session (next hop self implied here).\n");
		$adj_next_hop = 1;
		$next_hop_self = "$myip";
	} elsif ($peer_type eq "iBGP")
	{
		if ($next_hop_self eq "")
		{
			$adj_next_hop = 1;
			$next_hop_self = "$myip";
		} else
		{
			die "Next hop self IP address is not valid: $next_hop_self" if sub_checkip($next_hop_self);
			$adj_next_hop = 1;
		}
	}
} else
{
	$adj_next_hop = 0;
	$next_hop_self = "$myip";
};

die "Cannot open file $infile" 	if ( ($infile) && !( open (INPUT, $infile) ) );
close (INPUT);
die "Cannot open file $outfile" if ( ($outfile) && !( open (OUTPUT,">$outfile") ) );
close (OUTPUT);

die "Filter on input file actually requires an input file (-p)" if ( !($infile) && (%regex_filter) );
if (%regex_filter)
{
	foreach my $key (keys %regex_filter)
	{
		die "Key " . uc($key) . " is not valid.\n" 		unless (uc($key) =~ /NEIG|NLRI|ASPT|ORIG|NXHP|LOCP|MED|COMM|ATOM|AGG/);
		die "Regex " . $regex_filter{$key} . " is bogus.\n" 	unless ( eval { qr/$regex_filter{$key}/ } );
		# convert hash keys to upper case
		$regex_filter{uc($key)} = delete $regex_filter{$key};
	}
}

sub_debug ("m", "---------------------------------------- CONFIG SUMMARY --------------------------------------------------\n");
sub_debug ("m", "Configured for an $peer_type session between me (ASN$myas, $myip) and peer (ASN$peeras, $peerip).\n");
sub_debug ("m", "Using $keepalive seconds as KeepAlive value and $holdtime seconds as HoldTime value for this peer.\n");
sub_debug ("m", "Will not listen at $myip, 179/tcp.\n")						if $nolisten;
sub_debug ("m", "Generating verbose output, level $verbose.\n") 				if $verbose;
sub_debug ("m", "Will use prefixes from file $infile.\n") 					if $infile;
sub_debug ("m", "Will write sent and received UPDATEs to file $outfile.\n") 			if $outfile;
sub_debug ("m", "Maximum number of prefixes to be advertised: $prefix_limit.\n") 		if ($prefix_limit);
sub_debug ("m", "Will spoof next hop address to $next_hop_self.\n") 				if (($adj_next_hop) && ($peer_type eq "iBGP"));
sub_debug ("m", "Will set next hop address to $next_hop_self because of eBGP peering.\n") 	if ($peer_type eq "eBGP");
if (%regex_filter)
{
	sub_debug ("m", "Will apply filter to input file:\n");
	foreach my $key (sort keys %regex_filter)
	{
		sub_debug ("m", "\t" . uc($key) . " =~ /" .  $regex_filter{$key} . "/\n");
	}
}
sub_debug ("m", "----------------------------------------------------------------------------------------------------------\n");

if ($dry)
{
	die "Prefix file (-f) required for dry run!\n" if not ($infile);
	sub_debug ("m", "Starting dry run.\n");
	sub_update_from_file();
	sub_debug ("m", "Dry run done, exiting.\n");
	exit;
}

my $bgp  = Net::BGP::Process->new( ListenAddr => $myip );
my $peer = Net::BGP::Peer->new(
        Start    		=> 0,
        ThisID   		=> $myip,
        ThisAS   		=> $myas,
        PeerID   		=> $peerip,
        PeerAS   		=> $peeras,
	HoldTime		=> $holdtime,
	KeepAliveTime		=> $keepalive,
	Listen			=> !($nolisten),
        KeepaliveCallback    	=> \&sub_keepalive_callback,
        UpdateCallback       	=> \&sub_update_callback,
        NotificationCallback 	=> \&sub_notification_callback,
        ErrorCallback        	=> \&sub_error_callback,
        OpenCallback        	=> \&sub_open_callback,
        ResetCallback        	=> \&sub_reset_callback,
);

# full update required
my $full_update = 0;

$bgp->add_peer($peer);
$peer->add_timer(\&sub_timer_callback, 10);
$bgp->event_loop();

sub sub_debug
{
	my $level = shift(@_);
	my $msg   = shift(@_);

	print $msg if ($level eq "m");				# mandatory
	print $msg if ($level eq "e");				# error
	print $msg if ($level eq "u");				# UPDATE
	print $msg if ( ($level eq "i") && ($verbose >= 1) );	# informational
	print $msg if ( ($level eq "d") && ($verbose >= 2) );	# debug


	if ( ($outfile) && ($level eq "u") )
	{
		open (OUTPUT,">>$outfile") || die "Cannot open file $outfile";
		print OUTPUT "$msg";
		close (OUTPUT);
	}
}

sub sub_checkip
{
	("@_" !~ /^([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])$/)
	? 1 : 0;

}

sub sub_checkas
{
	("@_" !~ /^([1-9]\d?\d?\d?|[1-5]\d\d\d\d|6[0-4]\d\d\d|65[0-4]\d\d|655[0-2]\d|6553[0-5])$/) ? 1 : 0;
}

sub sub_checkaspath
{
	("@_" !~ /^(([1-9]\d?\d?\d?|[1-5]\d\d\d\d|6[0-4]\d\d\d|65[0-4]\d\d|655[0-2]\d|6553[0-5]))(((\s| \{|,)([1-9]\d?\d?\d?|[1-5]\d\d\d\d|6[0-4]\d\d\d|65[0-4]\d\d|655[0-2]\d|6553[0-5]))\}?)*$|^$/) ? 1 : 0;
}


sub sub_checkcommunity
{
	("@_" !~ /^(([0-9]\d?\d?\d?|[1-5]\d\d\d\d|6[0-4]\d\d\d|65[0-4]\d\d|655[0-2]\d|6553[0-5])\:([1-9]\d?\d?\d?|[1-5]\d\d\d\d|6[0-4]\d\d\d|65[0-4]\d\d|655[0-2]\d|6553[0-5]))( (([1-9]\d?\d?\d?|[1-5]\d\d\d\d|6[0-4]\d\d\d|65[0-4]\d\d|655[0-2]\d|6553[0-5])\:([1-9]\d?\d?\d?|[1-5]\d\d\d\d|6[0-4]\d\d\d|65[0-4]\d\d|655[0-2]\d|6553[0-5])))*$|^$/) ? 1 : 0;
}

sub sub_checkprefix
{
	("@_" !~ /^(([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\/(\d|[12]\d|3[0-2])\s?)+$/)
	? 1 : 0;

}

sub sub_connect_peer
{
	my ($peer) = shift(@_);
    	my $peerid = $peer->peer_id();
        my $peeras = $peer->peer_as();

	$bgp->remove_peer($peer);
	$bgp->add_peer($peer);

	$full_update = 0;
}

sub sub_timer_callback
{
        my ($peer) = shift(@_);
        my $peerid = $peer->peer_id();
        my $peeras = $peer->peer_as();

	if (! $peer->is_established)
	{
		sub_debug ("d", "Loop: trying to establish session.\n");
		sub_connect_peer($peer);

	} elsif (($infile) && (! $full_update))
	{
		sub_debug ("m","Sending full update.\n");

		$full_update = 1;
		sub_update_from_file($peer);

		sub_debug ("m", "Full update sent.\n");
	} else
	{
		sub_debug ("d", "Nothing to do.\n");
	}
}

sub sub_open_callback
{
        my ($peer) = shift(@_);
        my $peerid = $peer->peer_id();
        my $peeras = $peer->peer_as();
        sub_debug ("i","Connection established with peer $peerid, AS $peeras.\n");
	$full_update = 0;
}

sub sub_reset_callback
{
        my ($peer) = shift(@_);
        my $peerid = $peer->peer_id();
        my $peeras = $peer->peer_as();
        sub_debug ("e","Connection reset with peer $peerid, AS $peeras.\n");

}

sub sub_keepalive_callback
{
	my ($peer) = shift(@_);
	my $peerid = $peer->peer_id();
	my $peeras = $peer->peer_as();
	sub_debug ("d","Keepalive received from peer $peerid, AS $peeras.\n");

}

sub sub_update_callback
{
	my ($peer) = shift(@_);
	my ($update) = shift(@_);
	my $peerid =  $peer->peer_id();
	my $peeras =  $peer->peer_as();
	my $nlri_ref = $update->nlri();
	my $locpref = $update->local_pref();
	my $med = $update->med();
	my $aspath = $update->as_path();
	my $comm_ref = $update->communities();
	my $origin = $update->origin();
	my $nexthop = $update->next_hop();
	my $aggregate = $update->aggregator();

	sub_debug ("u","Update received from peer [$peerid], ASN [$peeras]: ");

	my @prefixes = @$nlri_ref;
	sub_debug ("u","prfx [@prefixes] ");

	sub_debug ("u", "aspath [$aspath] ");
	sub_debug ("u", "nxthp [$nexthop] ")	if ($nexthop);
	sub_debug ("u", "locprf [$locpref] ") 	if ($locpref);
	sub_debug ("u", "med [$med] ")		if ($med);
	sub_debug ("u", "comm ");

	my @communities = @$comm_ref;
	sub_debug ("u", "[@communities] " );

	sub_debug ("u", "orig [IGP] ") if ($origin eq "0");
	sub_debug ("u", "orig [EGP] ") if ($origin eq "1");
	sub_debug ("u", "orig [INCOMPLETE] ") if ($origin eq "2");

	my @aggregator = @$aggregate;
	sub_debug ("u", "agg [@aggregator]\n");

}

sub sub_notification_callback
{
	my ($peer) = shift(@_);
	my ($msg) = shift(@_);

       	my $peerid =  $peer->peer_id();
        my $peeras =  $peer->peer_as();
	my $error_code = $msg->error_code();
	my $error_subcode = $msg->error_subcode();
	my $error_data = $msg->error_data();

	my $error_msg = $BGP_ERROR_CODES{ $error_code }{ __NAME__ };
	sub_debug ("e", "Notification received: type [$error_msg]");
	sub_debug ("e", " subcode [" . $BGP_ERROR_CODES{ $error_code }{ $error_subcode } . "]")	if ($error_subcode);
	sub_debug ("e", " additional data: [" .  unpack ("H*", $error_data) . "]") 		if ($error_data);
	sub_debug ("e", "\n");

}

sub sub_error_callback
{
	my ($peer) = shift(@_);
	my ($msg) = shift(@_);

       	my $peerid = $peer->peer_id();
        my $peeras = $peer->peer_as();
	my $error_code = $msg->error_code();
	my $error_subcode = $msg->error_subcode();
	my $error_data = $msg->error_data();

	my $error_msg = $BGP_ERROR_CODES{ $error_code }{ __NAME__ };
	sub_debug ("e", "Error occured: type [$error_msg]");
	sub_debug ("e", " subcode [" . $BGP_ERROR_CODES{ $error_code }{ $error_subcode } . "]")	if ($error_subcode);
	sub_debug ("e", " additional data: [" .  unpack ("H*", $error_data) . "]") 		if ($error_data);
	sub_debug ("e", "\n");
}

sub sub_update_from_file
{

	my ($peer) = shift(@_);
	open (INPUT, $infile) || die "Could not open $infile\n";
	my $cur = 1;

	while (<INPUT>)
	{
		my $line = $_;
		chomp($line);

		my @nlri = split /\|/,$line;

		# Filter based on advertising neighbor?
		if (($regex_filter{"NEIG"}) && ($nlri[3] !~ qr/$regex_filter{"NEIG"}/) )
		{
			sub_debug ("d", "Line [$.], Neighbor [$nlri[3]] skipped due to NEIG filter (value was: $nlri[3]).\n");
			next;
		};

		# Prefix valid?
		if (sub_checkprefix($nlri[5]))
		{
			sub_debug ("d", "Line [$.],Prefix [$nlri[5]] failed because of wrong prefix format.\n");
			next;
		};

		# Filter based on prefix?
		if (($regex_filter{"NLRI"}) && ($nlri[5] !~ qr/$regex_filter{"NLRI"}/) )
		{
			sub_debug ("d", "Line [$.], Prefix [$nlri[5]] skipped due to NLRI filter (value was: $nlri[5]).\n");
			next;
		};

		my $prefix = $nlri[5];

		# AS_PATH valid?
		if (sub_checkaspath($nlri[6]))
		{
			sub_debug ("d", "Line [$.], Prefix [$prefix] failed because of wrong AS_PATH format.\n");
			next;
		};

		# Filter based on AS_PATH?
		if (($regex_filter{"ASPT"}) && ($nlri[6] !~ qr/$regex_filter{"ASPT"}/) )
		{
			sub_debug ("d", "Line [$.], Prefix [$prefix] skipped due to ASPT filter (value was: $nlri[6]).\n");
			next;
		};

		my $aspath = Net::BGP::ASPath->new($nlri[6]);

		# add own AS for eBGP adjacencies
                $aspath += "$myas" if ($peer_type eq "eBGP");

		# Community valid?
		if (sub_checkcommunity($nlri[11]))
		{
			sub_debug ("d", "Line [$.], Prefix [ $prefix ] failed because of wrong COMMUNITY format.\n");
			next;
		};

		# Filter based on COMMUNITY?
		if (($nlri[11]) && ($regex_filter{"COMM"}) && ($nlri[11] !~ qr/$regex_filter{"COMM"}/) )
		{
			sub_debug ("d", "Line [$.], Prefix [$prefix] skipped due to COMM filter (value was: $nlri[11]).\n");
			next;
		};

		my @communities = split / /,$nlri[11];


		# Filter based on LOCAL_PREF?
		# note: line is skipped if LOCP filter is specified, but line doesnt contain any LOCAL_PREF values
		# also, for iBGP peerings, LOCAL_PREF is forced to $default_local_pref if none is provided
		my $local_pref;
		if  (($nlri[9] ne "0") && ($nlri[9] ne ""))
		{
			if ( ($regex_filter{"LOCP"}) && ($nlri[9] !~ qr/$regex_filter{"LOCP"}/) )
			{
				sub_debug ("d", "Line [$.], Prefix [$prefix] skipped due to LOCP filter (value was: $nlri[9]).\n");
				next;
			} else
			{
				$local_pref = $nlri[9];
			}
		} elsif ($regex_filter{"LOCP"})
		{
			sub_debug ("d", "Line [$.], Prefix [$prefix] skipped - doesnt contain LOCAL_PREF value, but LOCP filter specified.\n");
			next;
		} elsif ($peer_type eq "iBGP")
		{
			sub_debug ("d", "Line [$.], Prefix [$prefix] - doesnt contain valid LOCAL_PREF value but we peer via iBGP (value forced to $default_local_pref).\n");
			$local_pref = $default_local_pref;
		};

		# Filter based on MED?
		# note: line is skipped if MED filter is specified, but line doesnt contain any MED values
		# (use -f MED='' in such a case)
		my $med;
		if  (($nlri[10] ne "0") && ($nlri[10] ne ""))
		{
			if ( ($regex_filter{"MED"}) && ($nlri[10] !~ qr/$regex_filter{"MED"}/) )
			{
				sub_debug ("d", "Line [$.], Prefix [$prefix] skipped due to MED filter (value was: $nlri[10]).\n");
				next;
			} else
			{
				$med = $nlri[10];
			}
		} else
		{
			if ($regex_filter{"MED"})
			{
				sub_debug ("d", "Line [$.], Prefix [$prefix] skipped - doesnt contain MED value, but MED filter specified.\n");
				next;
			}
		};

		# NEXT_HOP valid?
		if (sub_checkip($nlri[8]))
		{
			sub_debug ("d", "Line [$.], Prefix [ $prefix ] failed because of wrong NEXT_HOP format.\n");
			next;
		};

		# Filter based on NEXT_HOP?
		if (($regex_filter{"NXHP"}) && ($nlri[8] !~ qr/$regex_filter{"NXHP"}/) )
		{
			sub_debug ("d", "Line [$.], Prefix [$prefix] skipped due to NXHP filter (value was: $nlri[8]).\n");
			next;
		};
		my $nexthop = $nlri[8];

             	# force NEXT_HOP change for eBGP sessions, or if requested for iBGP sessions
                $nexthop = $next_hop_self if ( ($peer_type eq "eBGP") || ($peer_type eq "iBGP") && ($adj_next_hop) );

		my $origin;

		# Filter based on ORIGIN?
		# note: line is skipped if ORIGIN filter is specified, but line doesnt contain vaild ORIGIN values
		# if no filter is specified, and ORIGIN is empty, INCOMPLETE will be set
		if ($nlri[7]  =~ /^(IGP|EGP|INCOMPLETE)$/)
		{
			if (($regex_filter{"ORIG"}) && ($nlri[7] !~ qr/$regex_filter{"ORIG"}/) )
			{
				sub_debug ("d", "Line [$.], Prefix [$prefix] skipped due to ORIG filter (value was: $nlri[7]).\n");
				next;
			} else
			{
				$origin = 2;
				$origin = 0 if ($nlri[7] eq "IGP");
				$origin = 1 if ($nlri[7] eq "EGP");
			}
		} elsif (($nlri[7]) && ($regex_filter{"ORIG"}))
		{
			sub_debug ("d", "Line [$.], Prefix [$prefix] skipped - doesnt contain valid ORIGIN value, but ORIG filter specified.\n");
			next;
		} else
		{
			sub_debug ("d", "Line [$.], Prefix [$prefix] - doesnt contain valid ORIGIN value, ORIGIN adjusted to INCOMPLETE.\n");
			$origin = 2;
		};

		my @agg;

		# Filter based on AGGREGATOR?
		if (($nlri[13]) && ($nlri[13] ne ""))
		{
			if ( ($regex_filter{"AGG"}) && ($nlri[13] !~ qr/$regex_filter{"AGG"}/) )
			{
				sub_debug ("d", "Line [$.], Prefix [$prefix] skipped due to AGG filter (value was: $nlri[13]).\n");
				next;
			} else
			{
				@agg = split / /,$nlri[13];
			}
		} elsif (!($nlri[13]) && ($regex_filter{"AGG"}))
		{
			sub_debug ("d", "Line [$.], Prefix [$prefix] skipped - doesnt contain valid AGGREGATOR value, but AGG filter specified.\n");
			next;
	 	};

		my $atomic_agg;

		# Filter based on ATOMIC_AGGREGATE
		if (($nlri[12]) && ($nlri[12] ne ""))
		{
			if ( ($regex_filter{"ATOM"}) && ($nlri[12] !~ qr/$regex_filter{"ATOM"}/) )
			{
				sub_debug ("d", "Line [$.], Prefix [$prefix] skipped due to ATOM filter (value was: $nlri[12]).\n");
				next;
			} else
			{
				$atomic_agg = ($nlri[12] eq "AG") ? 1 : 0;
			}
		} elsif  (!($nlri[12]) && ($regex_filter{"ATOM"}))
		{
			sub_debug ("d", "Line [$.], Prefix [$prefix] skipped - doesnt contain valid ATOMIC_AGGREGATE value, but ATOM filter specified.\n");
			next;
	 	};

		sub_debug ("u", "Send Update: ") 			if (!$dry);
		sub_debug ("u", "Generated Update (not sent): ") 	if ($dry);
		sub_debug ("u", "prfx [$prefix] aspath [$aspath] ");
		sub_debug ("u", "locprf [$local_pref] ") 		if ($peer_type eq "iBGP");
		sub_debug ("u", "med [$med] ")				if ($med);
		sub_debug ("u", "comm [@communities] ")			if (@communities);
		sub_debug ("u", "orig [$nlri[7]] ");
		sub_debug ("u", "agg [@agg] ")				if (@agg);
		sub_debug ("u", "atom [$atomic_agg] ")			if ($atomic_agg);
		sub_debug ("u", "nxthp [$nexthop]\n");

		if (! $dry)
		{
			my $update = Net::BGP::Update->new(
       				NLRI            => [ $prefix ],
       				AsPath          => $aspath,
       				NextHop         => $nexthop,
				Origin		=> $origin,
			);
			$update->communities([ @communities ])	if (@communities);
			$update->aggregator([ @agg ])		if (@agg);
			$update->atomic_aggregate("1") 		if ($atomic_agg);
			$update->med($med)			if ($med);
			$update->local_pref($local_pref) 	if ($peer_type eq "iBGP");

			$peer->update($update);
		}
		$cur += 1;
		last if (($prefix_limit) && ($cur > $prefix_limit));
	}
	close (INPUT);
}
