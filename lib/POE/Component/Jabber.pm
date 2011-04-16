package POE::Component::Jabber;
use Filter::Template;
const XNode POE::Filter::XML::Node
use warnings;
use strict;

use POE;
use POE::Wheel::ReadWrite;
use POE::Wheel::SocketFactory;
use POE::Component::Jabber::Error;
use POE::Component::Jabber::Status;
use POE::Component::Jabber::ProtocolFactory;
use POE::Filter::XML;
use POE::Filter::XML::Node;
use POE::Filter::XML::NS(':JABBER');
use Digest::MD5('md5_hex');
use Carp;

use constant 
{
	'_pcj_config' 		=>	0,
	'_pcj_sock'			=>	1,
	'_pcj_sfwheel'		=>	2,
	'_pcj_wheel'		=>	3,
	'_pcj_id'			=>	4,
	'_pcj_sid'			=>	5,
	'_pcj_jid'			=>	6,
	'_pcj_helper'		=>	7,
	'_pcj_shutdown'		=>	8,
	'_pcj_parent'		=> 	9,
	'_pcj_input'		=>	10,
	'_pcj_error'		=>	11,
	'_pcj_status'		=>	12,
	'_pcj_pending'		=>	13,
	'_pcj_queue'		=>	14,
	'_pcj_init_finished'=>	15,

};

our $VERSION = '2.02';

sub new()
{
	my $class = shift;
	my $self = [];
	$self->[+_pcj_pending] = {};

	bless($self, $class);

	my $me = $class . '->new()';
	Carp::confess "$me requires an even number of arguments" if(@_ & 1);
	
	$self->_gather_options(\@_);
	
	my $args = $self->[+_pcj_config];

	$self->[+_pcj_helper] =
		POE::Component::Jabber::ProtocolFactory::get_guts
		(
			$args->{'connectiontype'}
		);

	$args->{'version'}	||= $self->[+_pcj_helper]->get_version();
	$args->{'xmlns'}	||= $self->[+_pcj_helper]->get_xmlns();
	$args->{'alias'}	||= $class;
	$args->{'stream'}	||= +XMLNS_STREAM;
	$args->{'debug'}	||= 0 ;
	$args->{'resource'}	||= md5_hex(time().rand().$$.rand().$^T.rand());
	

	if(!defined($args->{'stateparent'}))
	{
	
		my $session = $poe_kernel->get_active_session();

		if($session != $poe_kernel)
		{
			$self->[+_pcj_parent] = $session->ID();
		
		} else {

			Carp::confess "$me requires either an active session or the name" .
			' of a session that has the provided events.';
		}
	
	} else {

		$self->[+_pcj_parent] = $args->{'stateparent'};
	}

	Carp::confess "$me requires ConnectionType to be defined" if not defined
		$args->{'connectiontype'};
	Carp::confess "$me requires Username to be defined" if not defined
		$args->{'username'};
	Carp::confess "$me requires Password to be defined" if not defined
		$args->{'password'};
	Carp::confess "$me requires Hostname to be defined" if not defined
		$args->{'hostname'};
	Carp::confess "$me requires IP to be defined" if not defined
		$args->{'ip'};
	Carp::confess "$me requires Port to be defined" if not defined
		$args->{'port'};
	
	Carp::confess "$me requires InputEvent to be defined" if not defined
		$args->{'states'}->{'inputevent'};
		$self->[+_pcj_input] = $args->{'states'}->{'inputevent'};
	Carp::confess "$me requires ErrorEvent to be defined" if not defined
		$args->{'states'}->{'errorevent'};
		$self->[+_pcj_error] = $args->{'states'}->{'errorevent'};
	Carp::confess "$me requires StatusEvent to be defined" if not defined
		$args->{'states'}->{'statusevent'};
		$self->[+_pcj_status] = $args->{'states'}->{'statusevent'};
	
	$self->[+_pcj_helper] = 
		POE::Component::Jabber::ProtocolFactory::get_guts
		(
			$args->{'connectiontype'}
		);

	POE::Session->create
	(
		'object_states' =>
		[
			$self => 
			[
				'_start',
				'initiate_stream',
				'connect',
				'_connect',
				'connected',
				'disconnected',
				'shutdown',
				'output_handler',
				'debug_output_handler',
				'input_handler',
				'debug_input_handler',
				'return_to_sender',
				'connect_error',
				'server_error',
				'flushed',
				'_stop',
				'purge_queue',
				'debug_purge_queue',
			],

			$self =>
			{
				'reconnect' => 'connect'
			},

			$self->[+_pcj_helper] => $self->[+_pcj_helper]->get_states(),

		],
		
		'options' => 
		{
			'trace' => $args->{'debug'}, 
			'debug' => $args->{'debug'},
		},

		'heap' => $self,
	);


	return $self;

}

sub wheel()
{
	if(@_ > 1)
	{
		my ($self, $arg) = @_;
		$self->[+_pcj_wheel] = $arg;

	} else {

		return shift(@_)->[+_pcj_wheel];
	}
}

sub sock()
{
	if(@_ > 1)
	{
		my ($self, $arg) = @_;
		$self->[+_pcj_sock] = $arg;

	} else {

		return shift(@_)->[+_pcj_sock];
	}
}

sub config()
{
	if(@_ > 1)
	{
		my ($self, $arg) = @_;
		$self->[+_pcj_config] = $arg;

	} else {

		return shift(@_)->[+_pcj_config];
	}
}

sub sid()
{
	if(@_ > 1)
	{
		my ($self, $arg) = @_;
		$self->[+_pcj_sid] = $arg;
	
	} else {

		return shift(@_)->[+_pcj_sid];
	}
}

sub jid()
{
	if(@_ > 1)
	{
		my ($self, $arg) = @_;
		$self->[+_pcj_jid] = $arg;
	
	} else {

		return shift(@_)->[+_pcj_jid];
	}
}

sub parent()
{
	if(@_ > 1)
	{
		my ($self, $arg) = @_;
		$self->[+_pcj_parent] = $arg;
	
	} else {

		return shift(@_)->[+_pcj_parent];
	}
}

sub input()
{
	if(@_ > 1)
	{
		my ($self, $arg) = @_;
		$self->[+_pcj_input] = $arg;

	} else {

		return shift(@_)->[+_pcj_input];
	}
}

sub error()
{
	if(@_ > 1)
	{
		my ($self, $arg) = @_;
		$self->[+_pcj_error] = $arg;
	
	} else {

		return shift(@_)->[+_pcj_error];
	}
}

sub status()
{
	if(@_ > 1)
	{
		my ($self, $arg) = @_;
		$self->[+_pcj_status] = $arg;

	} else {

		return shift(@_)->[+_pcj_status];
	}
}

sub pending()
{
	if(@_ > 1)
	{
		my ($self, $arg) = @_;
		$self->[+_pcj_pending] = $arg;
	
	} else {

		return shift(@_)->[+_pcj_pending];
	}
}

sub queue()
{
	if(@_ > 1)
	{
		my ($self, $arg) = @_;
		$self->[+_pcj_queue] = $arg;

	} else {

		return shift(@_)->[+_pcj_queue];
	}
}

sub _gather_options()
{
	my ($self, $args) = @_;
	
	my $opts = {};

	while(@$args != 0)
	{
		my $key = lc(shift(@{$args}));
		my $value = shift(@{$args});
		
		if(ref($value) eq 'HASH')
		{
			my $hash = {};
			foreach my $sub_key (keys %$value)
			{
				$hash->{lc($sub_key)} = $value->{$sub_key};
			}
			$opts->{$key} = $hash;
			next;
		}
		$opts->{$key} = $value;
	}

	$self->[+_pcj_config] = $opts;

	return $self;
}

sub connect_error()
{
	my ($kernel, $self, $call, $code, $err) = @_[KERNEL, OBJECT, ARG0..ARG2];

	$self->debug_message("Connect Error: $call: $code -> $err\n");

	$kernel->post($self->[+_pcj_parent],
		$self->[+_pcj_error],
		+PCJ_CONNECTFAIL, 
		$call, $code, $err);
	
	return;
}

sub _start()
{	
	my ($kernel, $self) = @_[KERNEL, OBJECT];
	$kernel->alias_set($self->[+_pcj_config]->{'alias'});
	$self->_reset();

	if($self->[+_pcj_config]->{'debug'})
	{
		$kernel->state('output_handler', $self, 'debug_output_handler');
		$kernel->state('purge_queue', $self, 'debug_purge_queue');
	}

	$self->[+_pcj_queue] = [];

	return;
}

sub _stop()
{
	my ($kernel, $self) = @_[KERNEL, OBJECT];
	$kernel->alias_remove($_) for $kernel->alias_list();
	return;
}


sub _reset()
{
	my $self = shift;
	
	$self->[+_pcj_sid] = 0;
	$self->[+_pcj_pending] = {};
	$self->[+_pcj_init_finished] = 0;
	$self->[+_pcj_id] ||= Digest::SHA1->new();
	$self->[+_pcj_id]->add(time().rand().$$.rand().$^T.rand());
	$self->[+_pcj_wheel] = undef;
	$self->[+_pcj_sfwheel] = undef;
	$self->[+_pcj_sock]->close() if defined($self->[+_pcj_sock]);
	$self->[+_pcj_sock] = undef;
	return;
}

sub connect()
{
	my ($kernel, $self, $ip, $port) = @_[KERNEL, OBJECT, ARG0, ARG1];
	
	$self->[+_pcj_config]->{'ip'} = $ip if defined $ip;
	$self->[+_pcj_config]->{'port'} = $port if defined $port;

	$self->_reset();
	$kernel->yield('_connect');

	$kernel->post($self->[+_pcj_parent], $self->[+_pcj_status], +PCJ_CONNECT);
	return;
}

sub _connect()
{
	my ($kernel, $self) = @_[KERNEL, OBJECT];
	
	$self->[+_pcj_sfwheel] = POE::Wheel::SocketFactory->new
		(
			'RemoteAddress'	=>	$self->[+_pcj_config]->{'ip'},
			'RemotePort'	=>	$self->[+_pcj_config]->{'port'},
			'SuccessEvent'  =>  'connected',
			'FailureEvent'  =>  'connect_error',
		);
	
	
	$kernel->post(
		$self->[+_pcj_parent], 
		$self->[+_pcj_status], 
		+PCJ_CONNECTING);
	
	return;

}

sub _default()
{
	my ($event) = $_[ARG0];

	$_[OBJECT]->debug_message($event . ' was not caught');
}

sub return_to_sender()
{
	my ($kernel, $self, $session, $sender, $event, $node) = 
		@_[KERNEL, OBJECT, SESSION, SENDER, ARG0, ARG1];
	
	my $attrs = $node->get_attrs();
	my $pid;
	
	if(exists($attrs->{'id'}))
	{
		if(exists($self->[+_pcj_pending]->{$attrs->{'id'}}))
		{
			$self->debug_message('OVERRIDING USER DEFINED ID!');
			
			$pid = $self->[+_pcj_id]->add(
				$self->[+_pcj_id]->clone()->hexdigest())
					->clone()->hexdigest();

			$node->attr('id', $pid);
		}

		$pid = $attrs->{'id'};
		
	} else {
		
		$pid = $self->[+_pcj_id]->add(
			$self->[+_pcj_id]->clone()->hexdigest())
				->clone()->hexdigest();
		
		$node->attr('id', $pid);
	}
	
	my $state = $session == $sender ? 1 : undef;
	$self->[+_pcj_pending]->{$pid} = [];
	$self->[+_pcj_pending]->{$pid}->[0] = $sender->ID();
	$self->[+_pcj_pending]->{$pid}->[1] = $event;
	
	$kernel->yield('output_handler', $node, $state);

	$kernel->post($self->[+_pcj_parent], $self->[+_pcj_status], +PCJ_RTS_START);
	
	return;

}

sub connected()
{
	my ($kernel, $self, $sock) = @_[KERNEL, OBJECT, ARG0];

	$self->[+_pcj_sock] = $sock;
	$self->[+_pcj_sfwheel] = undef;

	my $input = $self->[+_pcj_helper]->get_input_event() || 
		Carp::confess('No input event defined in helper!');
	my $error = $self->[+_pcj_helper]->get_error_event();
	my $flushed = $self->[+_pcj_helper]->get_flushed_event();
	
	$kernel->state('input_handler', $self->[+_pcj_helper], $input);
	$kernel->state('server_error', $self->[+_pcj_helper], $error) if $error;
	$kernel->state('flushed', $self->[+_pcj_helper], $flushed) if $flushed;

	$self->[+_pcj_wheel] = POE::Wheel::ReadWrite->new
	(
		'Handle'		=> $self->[+_pcj_sock],
		'Filter'		=> POE::Filter::XML->new(),
		'InputEvent'	=> 'input_handler',
		'ErrorEvent'	=> 'server_error',
		'FlushedEvent'	=> 'flushed',
	);

	$kernel->yield('initiate_stream');

	$kernel->post($self->[+_pcj_parent], $self->[+_pcj_status], +PCJ_CONNECTED);
	
	return;
}

sub relinquish_states()
{
	my $self = shift;
	
	if($self->[+_pcj_config]->{'debug'})
	{
		$poe_kernel->state('input_handler', $self, 'debug_input_handler');

	} else {
		
		$poe_kernel->state('input_handler', $self, 'input_handler');
	}
	
	$poe_kernel->state('server_error', $self, 'server_error');
	$poe_kernel->state('flushed', $self, 'flushed');

	$self->[+_pcj_init_finished] = 1;
	return;
}

sub initiate_stream()
{
	my ($kernel, $self, $sender, $session) = 
		@_[KERNEL, OBJECT, SENDER, SESSION];

	my $element = XNode->new
	(
		'stream:stream',
		[
			'to', $self->[+_pcj_config]->{'hostname'}, 
			'xmlns', $self->[+_pcj_config]->{'xmlns'}, 
			'xmlns:stream', $self->[+_pcj_config]->{'stream'}, 
			'version', $self->[+_pcj_config]->{'version'}
		]
	)->stream_start(1);
	
	my $state = $session == $sender ? 1 : undef;
	$kernel->yield('output_handler', $element, $state);

	$kernel->post(
		$self->[+_pcj_parent], 
		$self->[+_pcj_status], 
		+PCJ_STREAMSTART);
	
	return;
}

sub disconnected()
{	
	my ($kernel, $self) = @_[KERNEL, OBJECT];
	$kernel->post(
		$self->[+_pcj_parent], 
		$self->[+_pcj_error], 
		+PCJ_SOCKETDISCONNECT);
	return;
}

sub flushed()
{
	my ($kernel, $self, $session) = @_[KERNEL, OBJECT, SESSION];

	if($self->[+_pcj_shutdown])
	{
		$kernel->call($session, 'disconnected');
		$kernel->post(
			$self->[+_pcj_parent], 
			$self->[+_pcj_status], 
			+PCJ_SHUTDOWN_FINISH);
	}
	
	return;
}
	

sub shutdown()
{
	my ($kernel, $self) = @_[KERNEL, OBJECT];

	my $node = XNode->new('stream:stream')->stream_end(1);
	
	$self->[+_pcj_shutdown] = 1;

	$self->[+_pcj_wheel]->put($node);

	$kernel->post($self->[+_pcj_parent], $self->[+_pcj_status], +PCJ_STREAMEND);
	$kernel->post(
		$self->[+_pcj_parent], 
		$self->[+_pcj_status], 
		+PCJ_SHUTDOWN_START);
	
	
	return;
}

sub debug_purge_queue()
{
	my ($kernel, $self, $sender, $session) = 
		@_[KERNEL, OBJECT, SENDER, SESSION];
	
	my $items = [];

	while(my $item = shift(@{$self->[+_pcj_queue]}))
	{
		push(@$items, $item);
	}
	
	$self->debug_message( 'Items pulled from queue: ' . scalar(@$items));
	
	my $state = $sender == $session ? 1 : undef;

	foreach(@$items)
	{	
		$kernel->yield('output_handler', $_, $state);
	}

	return;
}

sub purge_queue()
{
	my ($kernel, $self, $sender, $session) =
		@_[KERNEL, OBJECT, SENDER, SESSION];
	
	my $items = [];

	while(my $item = shift(@{$self->[+_pcj_queue]}))
	{
		push(@$items, $item);
	}
	
	my $state = $sender == $session ? 1 : undef;

	foreach(@$items)
	{
		$kernel->yield('output_handler', $_, $state);
	}
	
	return;
}


sub debug_output_handler()
{
	my ($kernel, $self, $node, $state) = @_[KERNEL, OBJECT, ARG0, ARG1];

	if(defined($self->[+_pcj_wheel]))
	{
		if($self->[+_pcj_init_finished] || $state)
		{	
			$self->debug_message('Sent: ' . $node->to_str());
			$self->[+_pcj_wheel]->put($node);
			$kernel->post(
				$self->[+_pcj_parent],
				$self->[+_pcj_status],
				+PCJ_NODESENT);

		} else {
			
			$self->debug_message('Still initialising.');
			$self->debug_message('Queued: ' . $node->to_str());
			push(@{$self->[+_pcj_queue]}, $node);
			$self->debug_message(
				'Queued COUNT: ' . scalar(@{$self->[+_pcj_queue]}));
			$kernel->post(
				$self->[+_pcj_parent],
				$self->[+_pcj_status],
				+PCJ_NODEQUEUED);
		}

	} else {
		
		$self->debug_message('There is no wheel present.');
		$self->debug_message('Queued: ' . $node->to_str());
		$self->debug_message(
			'Queued COUNT: ' . scalar(@{$self->[+_pcj_queue]}));
		push(@{$self->[+_pcj_queue]}, $node);
		$kernel->post(
			$self->[+_pcj_parent],
			$self->[+_pcj_error],
			+PCJ_SOCKETDISCONNECT);
		$kernel->post(
			$self->[+_pcj_parent],
			$self->[+_pcj_status],
			+PCJ_NODEQUEUED);
	}
	
	return;
}

sub output_handler()
{
	my ($kernel, $self, $node, $state) = @_[KERNEL, OBJECT, ARG0, ARG1];

	if(defined($self->[+_pcj_wheel]))
	{
		if($self->[+_pcj_init_finished] || $state)
		{
			$self->[+_pcj_wheel]->put($node);
			$kernel->post(
				$self->[+_pcj_parent], 
				$self->[+_pcj_status], 
				+PCJ_NODESENT);
		
		} else {

			push(@{$self->[+_pcj_queue]}, $node);
			$kernel->post(
				$self->[+_pcj_parent],
				$self->[+_pcj_status],
				+PCJ_NODEQUEUED);
		}

	} else {

		push(@{$self->[+_pcj_queue]}, $node);
		$kernel->post(
			$self->[+_pcj_parent],
			$self->[+_pcj_error],
			+PCJ_SOCKETDISCONNECT);
		$kernel->post(
			$self->[+_pcj_parent],
			$self->[+_pcj_status],
			+PCJ_NODEQUEUED);
	}
	return;
}

sub input_handler()
{
	my ($kernel, $self, $node) = @_[KERNEL, OBJECT, ARG0];

	$kernel->post(
		$self->[+_pcj_parent], 
		$self->[+_pcj_status], 
		+PCJ_NODERECEIVED);
	
	my $attrs = $node->get_attrs();		
	
	if(exists($attrs->{'id'}))
	{
		if(defined($self->[+_pcj_pending]->{$attrs->{'id'}}))
		{
			my $array = delete $self->[+_pcj_pending]->{$attrs->{'id'}};
			$kernel->post($array->[0], $array->[1], $node);
			$kernel->post(
				$self->[+_pcj_parent], 
				$self->[+_pcj_status], 
				+PCJ_RTS_FINISH);
			return;
		}
	}

	$kernel->post($self->[+_pcj_parent], $self->[+_pcj_input], $node);
	return;
}

sub debug_input_handler()
{
	my ($kernel, $self, $node) = @_[KERNEL, OBJECT, ARG0];

	$kernel->post(
		$self->[+_pcj_parent], 
		$self->[+_pcj_status], 
		+PCJ_NODERECEIVED);
	
	$self->debug_message("Recd: ".$node->to_str());

	my $attrs = $node->get_attrs();

	if(exists($attrs->{'id'}))
	{
		if(defined($self->[+_pcj_pending]->{$attrs->{'id'}}))
		{
			my $array = delete $self->[+_pcj_pending]->{$attrs->{'id'}};
			$kernel->post($array->[0], $array->[1], $node);
			$kernel->post(
				$self->[+_pcj_parent], 
				$self->[+_pcj_status], 
				+PCJ_RTS_FINISH);
			return;
		}
	}
	
	$kernel->post($self->[+_pcj_parent], $self->[+_pcj_input], $node);
	return;
}

sub server_error()
{
	my ($kernel, $self, $call, $code, $err) = @_[KERNEL, OBJECT, ARG0..ARG2];
	
	$self->debug_message("Server Error: $call: $code -> $err\n");
	
	$self->[+_pcj_wheel] = undef;

	$kernel->post($self->[+_pcj_parent],
		$self->[+_pcj_error], 
		+PCJ_SOCKETFAIL, 
		$call, $code, $err);
	return;
}

sub debug_message()
{	
	my $self = shift;
	warn "\n", scalar (localtime (time)), ': ' . shift(@_) ."\n";

	return;
}

1;

__END__

=pod

=head1 NAME

POE::Component::Jabber - A POE Component for communicating over Jabber

=head1 SYNOPSIS

 use POE;
 use POE::Component::Jabber;
 use POE::Component::Jabber::Error;
 use POE::Component::Jabber::Status;
 use POE::Component::Jabber::ProtocolFactory;
 use POE::Filter::XML::Node;
 use POE::Filter::XML::NS qw/ :JABBER :IQ /;

 POE::Component::Jabber->new(
   IP => 'jabber.server',
   PORT => '5222',
   HOSTNAME => 'jabber.server',
   USERNAME => 'username',
   PASSWORD => 'password',
   ALIAS => 'PCJ',
   STATES => {
	 StatusEvent => 'StatusHandler',
	 InputEvent => 'InputHandler',
	 ErrorEvent => 'ErrorHandler',
   }
 );
 
 $poe_kernel->post('PCJ', 'connect', $node);
 $poe_kernel->post('PCJ', 'output_handler', $node);
 $poe_kernel->post('PCJ', 'return_to_sender', $node);

=head1 DESCRIPTION

PCJ is a communications component that fits within the POE framework and
provides the raw low level footwork of initiating a connection, negotiatating
various protocol layers, and authentication necessary for the end developer
to focus more on the business end of implementing a client or service.

=head1 METHODS

=over 4

=item new()

Accepts many named, required arguments which are listed below. new() will
return a reference to the newly created reference to a PCJ object and should
be stored. There are many useful methods that can be called on the object to
gather various bits of information such as your negotiated JID.

=over 2

=item IP

The IP address in dotted quad, or the FQDN for the server.

=item PORT

The remote port of the server to connect.

=item HOSTNAME

The hostname of the server. Used in addressing.

=item USERNAME

The username to be used in authentication (OPTIONAL for jabberd14 service
connections).

=item PASSWORD

The password to be used in authentication.

=item RESOURCE

The resource that will be used for binding and session establishment 
(OPTIONAL: resources aren't necessary for initialization of service oriented
connections, and if not provided for client connections will be automagically 
generated).

=item ALIAS

The alias the component should register for use within POE. Defaults to
the class name.

=item CONNECTIONTYPE

This is the type of connection you wish to esablish. Please use the constants
provided in PCJ::ProtocolFactory for the basis of this argument. There is no
default.

=item VERSION

If for whatever reason you want to override the protocol version gathered from
your ConnectionType, this is the place to do it. Please understand that this 
value SHOULD NOT be altered, but it is documented here just in case.

=item XMLNS

If for whatever reason you want to override the protocol's default XML
namespace that is gathered from your ConnectionType, use this variable. Please
understand that this value SHOULD NOT be altered, but is documented here just
in case.

=item STREAM

If for whatever reason you want to override the xmlns:stream attribute in the
<stream:stream/> this is the argument to use. This SHOULD NOT ever need to be
altered, but it is available and documented just in case.

=item STATEPARENT

The alias or session id of the session you want the component to contact. This
is optional provided to instantiate PCJ within another POE::Session. In that
case, that session will be assumed to be the recepient of events.

=item STATES

=over 2

=item StatusEvent

The StatusEvent will receive an event for every status change within PCJ. This
is useful for providing feedback to the end user on what exactly the client or
service is doing. Please see POE::Component::Jabber::Status for exported 
constants and what they signify.

=item InputEvent

The InputEvent will receive an event for every jabber packet that comes through
the connection once fully initialized. ARG0 will be a reference to a 
POE::Filter::XML::Node. Please see POE::Filter::XML::Node documentation for
ways to get the information out of the Nodes and construct Nodes of your own.

=item ErrorEvent

The error event will be fired upon a number of detected error conditions within
PCJ. Please see the POE::Component::Jabber::Error documentation for possible 
error states.

=back

=item DEBUG

If bool true, will enable debugging and tracing within the component. All XML
sent or received through the component will be printed to STDERR

=back

=item wheel() [Protected]

wheel() returns the currently stored POE::Wheel reference. If provided an
argument, that argument will replace the current POE::Wheel stored.

=item sock() [Protected]

sock() returns the current socket being used for communication. If provided an
argument, that argument will replace the current socket stored.

=item sid() [Protected]

sid() returns the session ID that was given by the server upon the initial
connection. If provided an argument, that argument will replace the current 
session id stored.

=item config() [Protected]

config() returns the configuration structure (HASH reference) of PCJ that is 
used internally. It contains values that are either defaults or were 
calculated based on arguments provided in the constructor. If provided an 
argument, that argument will replace the current configuration.

=item parent() [Public]

parent() returns either the session ID from the intantiating session, or the
alias or ID provided in the constructor. If provided an argument, that argument
will replace the current parent seesion ID or alias stored.

=item input() [Public]

input() returns the current event used by PCJ to deliver input events. If
provided an argument, that argument will replace the current input event used.

=item status() [Public]

status() returns the current event used by PCJ to deliver status events. If
provided an argument, that argument will replace the current status event used.

=item error() [Public]

error() returns the current event used by PCJ to deliver error events. If 
provided an argument, that argument will replace the current error event used.

=item pending() [Protected]

pending() returns a hash reference to the currently pending return_to_sender
transactions keyed by the 'id' attribute of the XML node. If provided an
argument, that argument will replace the pending queue.

=item queue() [Protected]

queue() returns an array reference containing the Nodes sent when there was 
no suitable initialized connection available. Index zero is the first Node
placed into the queue with index one being the second, and so on. See under
the EVENTS section, 'purge_queue' for more information.

=item _reset() [Private]

_reset() returns PCJ back to its initial state and returns nothing;

=item _gather_options() [Private]

_gather_options() takes an array reference of the arguments provided to new()
(ie. \@_) and populates its internal configuration with the values (the same 
configuration returned by config()).

=item relinquish_states() [Protected]

relinquish_states() is used by Protocol subclasses to return control of the
events back to the core of PCJ. It is typically called when the event 
PCJ_INIT_FINISH is fired to the status event handler.

=head1 EVENTS

=over 4

=item 'output_handler'

This is the event that you use to push data over the wire. It accepts only one
argument, a reference to a POE::Filter::XML::Node.

=item 'return_to_sender'

This event takes (1) a POE::Filter::XML::Node and gives it a unique id, and 
(2) a return event and places it in the state machine. Upon receipt of 
response to the request, the return event is fired with the response packet.
Note: the return event is post()ed in the context of the provided or default
parant session.

=item 'shutdown'

The shutdown event terminates the XML stream which in turn will trigger the
end of the socket's life.

=item 'connect' and 'reconnect'

This event can take (1) the ip address of a new server and (2) the port. This
event may also be called without any arguments and it will force the component
to [re]connect.

=item 'purge_queue'

If Nodes are sent to the output_handler when there isn't a fully initialized
connection, the Nodes are placed into a queue. PCJ will not automatically purge
this queue when a suitable connection DOES become available because there is no
way to tell if the packets are still valid or not. It is up to the end 
developer to decide this and fire this event. Packets will be setn in the order
in which they were received.

=back

=head1 NOTES AND BUGS

This is a connection broker. This should not be considered a first class
client or service. This broker basically implements whatever core
functionality is required to get the end developer to the point of writing
upper level functionality quickly. 

In the case of XMPP what is implemented:
XMPP Core.
A small portion of XMPP IM (session binding).

Legacy:
Basic authentication via iq:auth. (No presence management, no roster 
management)

JABBERD14:
Basic handshake. (No automatic addressing management of the 'from' attribute)

JABBERD20:
XMPP Core like semantics.
Domain binding. (No route packet enveloping or presence management)

With the major version increase, significant changes have occured in how PCJ
handles itself and how it is constructed. PCJ no longer connects when it is
instantiated. The 'connect' event must be post()ed for PCJ to connect.

For example implementations using all four current aspects, please see the 
examples/ directory in the distribution.

=head1 AUTHOR

Copyright (c) 2003-2007 Nicholas Perez. Distributed under the GPL.

=cut

