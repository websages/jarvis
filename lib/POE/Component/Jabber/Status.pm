package POE::Component::Jabber::Status;
use warnings;
use strict;

use constant
{
	'PCJ_CONNECT'			=> 0,
	'PCJ_CONNECTING'		=> 1,
	'PCJ_CONNECTED'			=> 2,
	'PCJ_STREAMSTART'		=> 3,
	'PCJ_SSLNEGOTIATE'		=> 4,
	'PCJ_SSLSUCCESS'		=> 5,
	'PCJ_AUTHNEGOTIATE'		=> 6,
	'PCJ_AUTHSUCCESS'		=> 7,
	'PCJ_BINDNEGOTIATE'		=> 8,
	'PCJ_BINDSUCCESS'		=> 9,
	'PCJ_SESSIONNEGOTIATE'	=> 10,
	'PCJ_SESSIONSUCCESS'	=> 11,
	'PCJ_NODESENT'			=> 12,
	'PCJ_NODERECEIVED'		=> 13,
	'PCJ_NODEQUEUED'		=> 14,
	'PCJ_RTS_START'			=> 15,
	'PCJ_RTS_FINISH'		=> 16,
	'PCJ_INIT_FINISHED'		=> 17,
	'PCJ_STREAMEND'			=> 18,
	'PCJ_SHUTDOWN_START'	=> 19,
	'PCJ_SHUTDOWN_FINISH'	=> 20,
};

require Exporter;
our $VERSION = '2.02';
our @ISA = qw/ Exporter /;
our @EXPORT = qw/ PCJ_CONNECT PCJ_CONNECTING PCJ_CONNECTED PCJ_STREAMSTART 
	PCJ_SSLNEGOTIATE PCJ_SSLSUCCESS PCJ_AUTHNEGOTIATE PCJ_AUTHSUCCESS 
	PCJ_BINDNEGOTIATE PCJ_BINDSUCCESS PCJ_SESSIONNEGOTIATE PCJ_SESSIONSUCCESS 
	PCJ_RECONNECT PCJ_NODESENT PCJ_NODERECEIVED PCJ_NODEQUEUED PCJ_RTS_START 
	PCJ_RTS_FINISH PCJ_INIT_FINISHED PCJ_STREAMEND PCJ_SHUTDOWN_START 
	PCJ_SHUTDOWN_FINISH /;

1;

__END__

=pod

=head1 NAME

POE::Component::Jabber::Status - useful constants for examining status

=head1 SYNOPSIS

PCJ::Status exports many useful constants for tracking the status of PCJ during
it's operation.

=head1 DESCRIPTION

PCJ, through the StatusEvent, will spit out various statuses for just about 
every step practical during normal operation. This includes being engaged during
the various Protocol specific portions that get loaded to handle the
dialects PCJ supports.

=head1 EXPORTS

Below are the exported constants with a brief explanation of what it is 
signalling to the end developer:

=over 4

=item PCJ_CONNECT

'connect' or 'reconnect' event has fired.

=item PCJ_CONNECTING

Connecting is now in process

=item PCJ_CONNECTED

Initial connection established

=item PCJ_STREAMSTART

A <stream:stream/> tag has been sent. The number of these events is variable 
depending on which Protocol is currently active (ie. XMPP will send upto three, 
while LEGACY will only send one).

=item PCJ_SSLNEGOTIATE

TLS/SSL negotiation has begun.
This Status event only is fired from XMPP and JABBERD20_COMPONENT connections.

=item PCJ_SSLSUCCESS

TLS/SSL negotiation has successfully complete. Socket layer is now encrypted. 
This Status event only is fired from XMPP and JABBERD20_COMPONENT connections.

=item PCJ_AUTHNEGOTIATE

Whatever your authentication method (ie. iq:auth, SASL, <handshake/>, etc), it
is in process when this status is received.

=item PCJ_AUTHSUCCESS

Authentication was successful.

=item PCJ_BINDNEGOTIATE

For XMPP connections: this indicates resource binding negotiation has begun.

For JABBERD20_COMPONENT connections: domain binding negotiation has begun.

This Status event will not fire for any but the above two connection types.

=item PCJ_BINDSUCCESS

For XMPP connections: this indicates resource binding negotiation was 
sucessful.

For JABBERD20_COMPONENT connections: domain binding negotiation was successful.

This Status event will not fire for any but the above two connection types.

=item PCJ_SESSIONNEGOTIATE

Only for XMPP: This indicates session binding (XMPP IM) negotiation has begun.

=item PCJ_SESSIONSUCCESS

Only for XMPP: This indicates session binding (XMPP IM) negotiation was
successful.

=item PCJ_NODESENT

A Node has been placed, outbound, into the Wheel

=item PCJ_NODERECEIVED

A Node has been received.

=item PCJ_NODEQUEUED

An attempt to send a Node while there is no valid, initialized connection was 
caught. The Node has been queued. See PCJ event 'purge_queue' for details.

=item PCJ_RTS_START

A return_to_sender event has been fired for an outbound node.

=item PCJ_RTS_FINISH

A return_to_sender event has been fired for a matching inbound node.

=item PCJ_INIT_FINISHED

This event indicates that the connection is fully initialized and ready for use.

Watch for this event and begin packat transactions AFTER it has been fired.

=item PCJ_STREAMEND

A </stream:stream> Node has been sent. This indicates the end of the connection
and is called upon 'shutdown' of PCJ after the Node has been flushed.

=item PCJ_SHUTDOWN_START

This indicates that 'shutdown' has been fired and is currently in progress of 
tearing down the connection.

=item PCJ_SHUTDOWN_FINISH

This indicates that 'shutdown' is complete.

=back

=head1 NOTES

These Statuses should remain fairly constant, but like the note in PCJ::Error, 
these Status events are not written in stone. They are written in vim and are 
subject to change.

=head1 AUTHOR

(c) Copyright 2007 Nicholas Perez. Released under the GPL.

=cut
