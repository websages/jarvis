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
print Data::Dumper->Dump([$construct]);
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
                          'irc_default', 
                          'irc_001', 
                          'irc_public', 
                          'irc_ping', 
                          'irc_msg', 
                          'irc_public_reply', 
                          'irc_private_reply',
                          'authen',
                          'irc_whois',
                          'irc_join',
                          'elevate_priv',
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
    $self->{'irc_client'} = POE::Component::IRC->spawn(
                                                        nick    => $construct->{'nickname'},
                                                        ircname => $construct->{'ircname'},
                                                        server  => $construct->{'server'},
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
    $self->on_start(); 
    print STDERR ref($self)." started.\n"; 
}

sub stop  { 
    my $self = $_[OBJECT]; 
    my $kernel = $_[KERNEL];
    print STDERR ref($self)." stopped.\n"; 
}

sub states { my $self = $_[OBJECT]; return $self->{'states'};           }
sub alias { my $self = $_[OBJECT]; return $self->{'alias'};           }

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
sub on_start {
    my $self = $_[OBJECT];
    my $heap = $_[HEAP];
    # retrieve our component's object from the heap where we stashed it
    $self->{'irc_client'}->yield( register => 'all' );
    $self->{'irc_client'}->yield( connect => { } );
}

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
    print "Connected to ", $sender_heap->server_name(), "\n";
    for(@{ $self->{'channel_list'} }){
        # notify the persona that we're adding the channel and nick 
        # or there is no way for the persona to know what he's called in what channels
        $kernel->post(
                       $self->{'persona'}, 
                       'channel_add', 
                       { 
                         alias   => $self->alias(),
                         channel => $_,
                         nick    => $self->{'nickname'},
                       }
                     );
        # we join our channels
        $self->{'irc_client'}->yield( join => $_ );
    }
    return;
}

sub irc_public {
    my ($self, $kernel, $sender, $who, $where, $what) = @_[OBJECT, KERNEL, SENDER, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];

    #log everything before we do anything with it.
    $_[KERNEL]->post('logger', 'log', "$channel <$nick> $what");

print STDERR "( $what )\n";
    $what=~s/[^a-zA-Z0-9:!\@#\%^&*\[\]_+=\- ]//g;
print STDERR "1: < $what >\n";
    $what=~s/[\$\`\(]//g;
print STDERR "2: < $what >\n";
    $what=~s/[)]//g;
print STDERR "3: < $what >\n";
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
    # we need to remember 
    push(@{ $heap->{'pending'} }, { 'authen' => $msg, 'sender' => $sender->ID } );
    $self->{'irc_client'}->yield('whois', $msg->{'conversation'}->{'nick'} );
    # do nothing.
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
                push(@{ $heap->{'pending'} }, $reply );
            }
        }else{
            push(@{ $heap->{'pending'} }, $reply );
        }
    }
    return;
}

sub irc_join {
    my ($self, $kernel, $heap, $sender, $join, $channel) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0, ARG1];
    $join=~s/!.*//g;
    # tell the personality there is a new player
    print STDERR "[ $join ]\n";
    $kernel->post( $self->{'persona'}, 'channel_join', $join, $channel );
}
1;
