package POE::Component::Jabber::Legacy;
use Filter::Template;
const XNode POE::Filter::XML::Node
use warnings;
use strict;

use POE;
use POE::Component::Jabber::Error;
use POE::Component::Jabber::Status;
use POE::Filter::XML;
use POE::Filter::XML::Node;
use POE::Filter::XML::NS qw/ :JABBER :IQ /;
use Digest::SHA1 qw/ sha1_hex /;

use base('POE::Component::Jabber::Protocol');

our $VERSION = '2.02';

sub get_version()
{
	return '0.9';
}

sub get_xmlns()
{
	return +NS_JABBER_CLIENT;
}

sub get_states()
{
	return [ 'set_auth', 'init_input_handler' ];
}

sub get_input_event()
{
	return 'init_input_handler';
}

sub set_auth()
{
	my ($kernel, $heap) = @_[KERNEL, HEAP];
	
	my $config = $heap->config();
	my $node = XNode->new('iq', ['type', +IQ_SET, 'id', 'AUTH']);
	my $query = $node->insert_tag('query', ['xmlns', +NS_JABBER_AUTH]);

	$query->insert_tag('username')->data($config->{'username'});

	if($config->{'plaintext'})
	{
		$query->insert_tag('password')->data($config->{'password'});
	
	} else {

		my $hashed = sha1_hex($heap->sid().$config->{'password'});
		
		$query->insert_tag('digest')->data($hashed);
	}
	
	$query->insert_tag('resource')->data($config->{'resource'});

	$kernel->yield('output_handler', $node, 1);

	$heap->jid($config->{'username'} . '@' . $config->{'hostname'} . '/' .
		$config->{'resource'});
	
	return;
}

sub init_input_handler()
{
	my ($kernel, $heap, $node) = @_[KERNEL, HEAP, ARG0];
	
	my $config = $heap->config();

	if ($config->{'debug'})
	{
		$heap->debug_message( "Recd: ".$node->to_str() );
	}
	
	if($node->name() eq 'stream:stream')
	{
		$heap->sid($node->attr('id'));
		$kernel->yield('set_auth');
		$kernel->post($heap->parent(), $heap->status(), +PCJ_AUTHNEGOTIATE);
	
	} elsif($node->name() eq 'iq') {
	
		if($node->attr('type') eq +IQ_RESULT and $node->attr('id') eq 'AUTH')
		{
			$heap->relinquish_states();
			$kernel->post($heap->parent(), $heap->status(), +PCJ_AUTHSUCCESS);
			$kernel->post($heap->parent(),$heap->status(),+PCJ_INIT_FINISHED);
		
		} elsif($node->attr('type') eq +IQ_ERROR and 
			$node->attr('id') eq 'AUTH') {

			$heap->debug_message('Authentication Failed');
			$kernel->yield('shutdown');
			$kernel->post($heap->parent(), $heap->error(), +PCJ_AUTHFAIL);
		}
	}
}

1;

__END__

=pod

=head1 NAME

POE::Component::Jabber::Legacy - connect using the pre-XMPP Jabber protocol

=head1 SYNOPSIS

PCJ::Legacy is a Protocol implementation for the legacy (ie. Pre-XMPP) Jabber
protocol.

=head1 DESCRIPTION

PCJ::Legacy implements the simple iq:auth authentication mechanism defined in
the deprecated XEP at http://www.xmpp.org/extensions/xep-0078.html. This
Protocol class is mainly used for connecting to legacy jabber servers that do
not conform the to XMPP1.0 RFC.

=head1 METHODS

Please see PCJ::Protocol for what methods this class supports.

=head1 EVENTS

Listed below are the exported events that end up in PCJ's main session:

=over 2

=item set_auth

This handles construction and sending of the iq:auth query.

=item init_input_handler

This is our main entry point. This is used by PCJ to deliver all input events 
until we are finished. Also handles responses to authentication.

=head1 NOTES AND BUGS

Ideally, this class wouldn't be necessary, but there is a large unmoving mass 
of entrenched users and administrators that refuse to migrate to XMPP. It
largely doesn't help that debian still ships jabberd 1.4.3 which does NOT 
support XMPP.

Currently, [JX]EP-77 is NOT supported, but it is planned for the next release.
Until then, all authentication failures are treated as fatal and PCJ will be
shutdown.

=head1 AUTHOR

Copyright (c) 2003-2007 Nicholas Perez. Distributed under the GPL.

=cut
