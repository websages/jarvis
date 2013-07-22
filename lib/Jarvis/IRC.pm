package Jarvis::IRC;
use strict;
use warnings;
use POE;
use AppConfig;
use FileHandle;
use File::Temp qw/ :mktemp  /;
use Log::Dispatch::Config;
use Log::Dispatch::Configurator::Hardwired;
use POE qw(Wheel::Run);
use POE qw(Component::IRC);
use POE qw(Component::IRC::State);
use POE qw(Component::Client::LDAP);
use POE qw(Component::Logger);
use Time::Local;
use Data::Dumper;
use YAML;

sub new { 
   my $class = shift; 
   $class = ref($class)||$class;
   my $self = {}; 
   my $construct = shift if @_;
    # list of required constructor elements
    $self->{'must'} = ["channel_list","nickname","alias","persona","domain"];

    # hash of optional constructor elements (key), and their default (value) if not specified
    $self->{'may'} = { };

    # set our required values fron the constructor or the defaults
    foreach my $attr (@{ $self->{'must'} }){
         if(defined($construct->{$attr})){
             $self->{$attr} = $construct->{$attr};
         }else{
             print STDERR "Required session constructor attribute [$attr] not defined. ";
             print STDERR "Unable to define ". __PACKAGE__ ." object\n";
             return undef;
         }
    }

    # set our optional values fron the constructor or the defaults
    foreach my $attr (keys(%{ $self->{'may'} })){
         if(defined($construct->{$attr})){
             $self->{$attr} = $construct->{$attr};
         }else{
             $self->{$attr} = $self->{'may'}->{$attr};
         }
    }

    bless($self,$class); 
    $self->{'states'} = [
                          'start', 
                          'stop', 
                          'say_public', 
                          'irc_default', 
                          'irc_001', 
                          'irc_401', 
                          'irc_msg', 
                          'irc_ping', 
                          'irc_private_reply',
                          'irc_public', 
                          'irc_public_reply', 
                          'authen',
                          'irc_whois',
                          'irc_join',
                          'join',
                          'elevate_priv',
                          'channel_members',
                          'irc_318',
                          'irc_353',
                          'irc_invite',
                          'say_public',
                          'irc_error',
                          'irc_quit',
                          'invite',
                        ];
    #$self->{'states'} = { 
    #                      start                => 'start',
    #                      stop                 => 'stop',
    #                      irc_default          => 'irc_default',
    #                      irc_001              => 'irc_001',
    #                      irc_public           => 'irc_public',
    #                      irc_ping             => 'irc_ping',
    #                      irc_msg              => 'irc_msg',
    #                      irc_public_reply     => 'irc_public_reply',
    #                      irc_private_reply    => 'irc_private_reply',
    #                   };
print STDERR Data::Dumper->Dump([{
                                                        nick     => $construct->{'nickname'},
                                                        ircname  => $construct->{'ircname'},
                                                        server   => $construct->{'server'},
                                                        port     => $construct->{'port'},
                                                        username => $construct->{'username'},
                                                        password => $construct->{'password'},
                                                        usessl   => $construct->{'usessl'},
                                 }]                     ) ;
    $self->{'irc_client'} = POE::Component::IRC->spawn(
                                                        nick     => $construct->{'nickname'},
                                                        ircname  => $construct->{'ircname'},
                                                        server   => $construct->{'server'},
                                                        port     => $construct->{'port'},
                                                        username => $construct->{'username'},
                                                        password => $construct->{'password'},
                                                        usessl   => $construct->{'usessl'},
                                                      ) 
        or $self->error("Cannot connect to IRC $construct->{'server'} $!");
    return $self 
}

################################################################################
# POE::Builder expects 'stop', 'start', and 'states', and 'alias'
################################################################################
sub start { 
    my $self = $_[OBJECT]; 
    my $kernel = $_[KERNEL];
    my $session = $_[SESSION];
    $self->{'irc_client'}->yield( register => 'all' );
    $self->{'irc_client'}->yield( connect => { } );
}

sub stop  { 
    my $self = $_[OBJECT]; 
    my $kernel = $_[KERNEL];
    #$self->{'irc_client'}->yield( 'disconnect' );
    #if($self->{'irc_client'}->yield( 'connected' )){
    #    print STDERR ref($self)." disconnected.\n"; 
    #}else{
    #    print STDERR ref($self)." failed to disconnect.\n"; 
    #}
    $self->{'irc_client'}->yield( 'quit' => 'terminated.');
    $self->{'irc_client'}->yield( 'unregister' => 'all' );
}

sub states { my $self = $_[OBJECT]; return $self->{'states'}; }
sub alias { my $self = $_[OBJECT]; return $self->{'alias'};   }

# A formatting function so we can use "here" statements and still have readable code
sub indented_yaml{
     my $self = shift;
     my $iyaml = shift if @_;
     return undef unless $iyaml;
     my @lines = split('\n', $iyaml);
     my $min_indent=-1;
     foreach my $line (@lines){
         my @chars = split('',$line);
         my $spcidx=0;
         foreach my $char (@chars){
             if($char eq ' '){
                 $spcidx++;
             }else{
                 if(($min_indent == -1) || ($min_indent > $spcidx)){
                     $min_indent=$spcidx;
                 }
             }
         }
     }
     foreach my $line (@lines){
         $line=~s/ {$min_indent}//;
     }
     my $yaml=join('\n',$iyaml);
     return YAML::Load($yaml);

}
################################################################################
# irc methods;
################################################################################

sub irc_default {
    my $self = $_[OBJECT];
    my ($event, $args) = @_[ARG0 .. $#_];
    my @output = ( "$event: " );

    my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];
    for my $arg (@$args) {
        if ( ref $arg eq 'ARRAY' ) {
            push( @output, '[' . join(', ', @$arg ) . ']' );
        }
        else {
            push ( @output, "'$arg'");
        }
    }
    $_[KERNEL]->post('logger', 'log', join ' ', @output);
    return 0;
}

sub irc_001 {
    my ($self, $kernel, $sender) = @_[OBJECT, KERNEL, SENDER];
    # Since this is an irc_* event, we can get the component's object by
    # accessing the heap of the sender. Then we register and connect to the
    # specified server.
    my $sender_heap = $sender->get_heap();
    #print "Connected to ", $sender_heap->server_name(), "\n";
    for(@{ $self->{'channel_list'} }){ $kernel->yield('join',$_); }
    return;
}

sub join{
    my ($self, $kernel, $heap, $sender, $channel, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    # notify the persona that we're adding the channel and nick 
    # or there is no way for the persona to know what he's called in what channels
    $kernel->post(
                   $self->{'persona'}, 
                   'channel_add', 
                   { 
                     alias          => $self->alias(),
                     channel        => $channel,
                     nick           => $self->{'nickname'},
                     'output_event' => 'say_public',
                   }
                 );
    # we join our channels
    $self->{'irc_client'}->yield( join => $channel );
}

sub irc_public {
    my ($self, $kernel, $sender, $who, $where, $what) = @_[OBJECT, KERNEL, SENDER, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];

    #log everything before we do anything with it.
    $_[KERNEL]->post('logger', 'log', "$channel <$nick> $what");

    $what=~s/[^a-zA-Z0-9:?!\@#,\%^&*\[\]_+=\-"'<>\/\.! ~]//g;
    $what=~s/[\$\`\(]//g;
    $what=~s/[)]//g;
    #print STDERR "[$channel] $nick : $what\n";
    my $msg = { 
                'sender_alias' => $self->alias(),
                'reply_event'  => 'irc_public_reply',
                'conversation' => {
                                    'id'   => 1,
                                    'nick' => $nick,
                                    'room' => $channel,
                                    'body' => $what,
                                  }
              };
    $kernel->post("$self->{'persona'}", "input", $msg);

}

sub say_public {
    my ($self, $kernel, $heap, $sender, $channel, $statement) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0, ARG1];
    $self->{'irc_client'}->yield( privmsg => [ $channel ] => $statement );
}

sub irc_public_reply{
    my ($self, $kernel, $heap, $sender, $msg, $what) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my ( $who, $channel ) = ( $msg->{'conversation'}->{'nick'}, $msg->{'conversation'}->{'room'} );
    $self->{'irc_client'}->yield( privmsg => [ $channel ] => $what );
}

sub elevate_priv{
    my ($self, $kernel, $heap, $sender, $nick, $channel) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    $self->{'irc_client'}->yield( 'mode', $channel." +o $nick" );
}

sub irc_msg {
    my ($self, $kernel, $sender, $who, $where, $what) = @_[OBJECT, KERNEL, SENDER, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];
    if ( $what =~m/(.+)/ ) {
        my $msg = { 
                    'sender_alias' => $self->alias(),
                    'reply_event'  => 'irc_private_reply',
                    'conversation' => {
                                        'id'     => 1,
                                        'nick'   => $nick,
                                        'room'   => $where,
                                        'body'   => $what,
                                        'direct' => 1,
                                      }
                  };
        $kernel->post("$self->{'persona'}", "input", $msg);
    }
    return;
}

sub irc_private_reply{
    my ($self, $kernel, $heap, $sender, $msg, $what) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my ( $who, $channel ) = ( $msg->{'conversation'}->{'nick'}, $msg->{'conversation'}->{'room'} );
    my $nick = ( split /!/, $who )[0];
    $self->{'irc_client'}->yield( privmsg => [ $nick ] => $what );
}

sub irc_ping {
    my $self = $_[OBJECT];
    # do nothing.
    return;
}

sub authen {
    my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
    # we need to remember this for when the reply comes back
    push(@{ $heap->{'pending'} }, { 'authen' => $msg, 'sender' => $sender->ID } );
    $self->{'irc_client'}->yield('whois', $msg->{'conversation'}->{'nick'} );
    # do nothing.
    return;
}

sub irc_401 {
    my ($self, $kernel, $heap, $sender, $server, $error, $error_array) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my $max=$#{ $heap->{'pending'} };
    my $count=0;
    while ($count++ <= $max){
        my $request = shift (@{ $heap->{'pending'} });
        if(defined($request->{'authen'})){
            if($error_array->[0] eq $request->{'authen'}->{'conversation'}->{'nick'}){
                $kernel->post(
                               $request->{'sender'}, 
                               'authen_reply', 
                               $request->{'authen'}, 
                               undef,
                             );
            }else{
                push(@{ $heap->{'pending'} }, $request );
            }
        }else{
            push(@{ $heap->{'pending'} }, $request );
        }
    }
    return;
}

sub irc_whois {
    my ($self, $kernel, $heap, $sender, $reply) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
    # look through our pending requests for authen
    my $max=$#{ $heap->{'pending'} };
    my $count=0;
    while ($count++ <= $max){
        my $request = shift (@{ $heap->{'pending'} });
        if(defined($request->{'authen'})){
            if($reply->{'nick'} eq $request->{'authen'}->{'conversation'}->{'nick'}){
                my $domain=$reply->{'host'};
                if($domain eq '127.0.0.1'){ $domain = $self->{'domain'}; }
                $kernel->post(
                               $request->{'sender'}, 
                               'authen_reply', 
                               $request->{'authen'}, 
                               $reply->{'user'} .'@'. $domain
                             );
            }else{
                push(@{ $heap->{'pending'} }, $request );
            }
        }else{
            push(@{ $heap->{'pending'} }, $request );
        }
    }
    return;
}

sub irc_318{
    my ($self, $kernel, $heap, $sender, @args)=@_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    #print STDERR Data::Dumper->Dump([@args]);
    return;
}

sub irc_join {
    my ($self, $kernel, $heap, $sender, $join, $channel) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0, ARG1];
    $join=~s/!.*//g;
    # tell the personality there is a new player
    $kernel->post( $self->{'persona'}, 'channel_join', $join, $channel );
}

# where the personality requests the channel members:
sub channel_members {
    my ($self, $kernel, $heap, $sender, $channel, $respond_to) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0, ARG1];
    push(@{ $heap->{'pending'} }, { 'channel_members' => $channel, 'sender' => $sender->ID, 'respond_to' => $respond_to } );
    $kernel->post( $self->{'irc_client'}, 'names', $channel );
}

# where the irc_server responds to our 'names' request
sub irc_353{
    # irc_names
    my ($self, $kernel, $heap, $sender, $server, $mstring, $mlist)=@_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    my ($channel, $members);
    if($mstring=~m/(\S+)\s+:(.*)/){
        $channel=$1;
        @{ $members } = split(" ",$2);
    }
    my $max=$#{ $heap->{'pending'} };
    my $count=0;
    while ($count++ <= $max){
        my $request = shift (@{ $heap->{'pending'} });
        if(defined($request->{'channel_members'})){
            #
            if($channel eq $request->{'channel_members'}){
                # this is the pending request that is waiting for a response
                $kernel->post($request->{'sender'},$request->{'respond_to'},$channel,$members);
            }else{
                # this is not the pending request we're answering, push it back on the pending list
                push(@{ $heap->{'pending'} }, $request );
            }
        }else{
            # this is not the pending request we're answering, push it back on the pending list
            push(@{ $heap->{'pending'} }, $request );
        }
    }
    return;
}

# where the irc_server responds to our 'names' request
sub irc_invite{
    my ($self, $kernel, $heap, $sender, @args)=@_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    $kernel->post( $self->{'persona'}, 'invite', @args );
    #$self->{'irc_client'}->yield( join => $args[1] );
    return;
}

sub invite{
    my ($self, $kernel, $heap, $sender, @args)=@_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    $self->{'irc_client'}->yield( invite => @args );
    return;
}

sub irc_error{
    my ($self, $kernel, $heap, $sender, @args)=@_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    $kernel->post($self->{'persona'},'connector_error',@args);
    return;
}

sub irc_quit{
    my ($self, $kernel, $heap, $sender, @args)=@_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    #print STDERR "irc_quit:\n";
    #print STDERR Data::Dumper->Dump([@args]);
    return;
}

1;
