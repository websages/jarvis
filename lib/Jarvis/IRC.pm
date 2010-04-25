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
    $self->{'must'} = ["channel_list","nickname","alias","persona"];

    # hash of optional constructor elements (key), and their default (value) if not specified
    $self->{'may'} = { };

    # set our required values fron the constructor or the defaults
    foreach my $attr (@{ $self->{'must'} }){
         if(defined($construct->{$attr})){
             $self->{$attr} = $construct->{$attr};
         }else{
             print STDERR "Required session constructor attribute [$attr] not defined. ";
             print STDERR "unable to define ". __PACKAGE__ ." object\n";
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
    $self->{'states'} = { 
                          _start               => '_start',
                          _stop                => '_stop',
                          irc_default          => '_default',
                          irc_001              => 'irc_001',
                          irc_public           => 'irc_public',
                          irc_ping             => 'irc_ping',
                          irc_msg              => 'irc_msg',
                       };
    $self->{'irc_client'} = POE::Component::IRC->spawn(
                                                        nick    => $construct->{'nickname'},
                                                        ircname => $construct->{'ircname'},
                                                        server  => $construct->{'server'},
                                                      ) 
        or $self->error("Cannot connect to IRC $construct->{'server'} $!");
    return $self 
}

################################################################################
# POE::Builder expects '_stop', '_start', and 'states', and 'alias'
################################################################################
sub _start { my $self = $_[OBJECT]; print STDERR ref($self)." start\n"; $self->on_start(); }


sub _stop  { my $self = $_[OBJECT]; print STDERR ref($self)." stop \n"; }
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

sub _default {
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
    my $self = $_[OBJECT];
    my $sender = $_[SENDER];
    # Since this is an irc_* event, we can get the component's object by
    # accessing the heap of the sender. Then we register and connect to the
    # specified server.
    my $sender_heap = $sender->get_heap();
    print "Connected to ", $sender_heap->server_name(), "\n";
    # we join our channels
    $self->{'irc_client'}->yield( join => $_ ) for (@{ $self->{'channel_list'} });
    return;
}

sub irc_public {
    my ($self, $kernel, $sender, $who, $where, $what) = @_[OBJECT, KERNEL, SENDER, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];


    print STDERR "KERNEL->post($self->{'persona'}, $self->{'persona'}_input)\n";
    $_[KERNEL]->post( "$self->{'persona'}", "$self->{'persona'}_input");

    #log everything before we do anything with it.
    $_[KERNEL]->post('logger', 'log', "$channel <$nick> $what");
    $what=~s/[^a-zA-Z0-9:!\@#\%^&*\[\]_+=\- ]//g;
    $what=~s/[\$\`\(]//g;
    $what=~s/[)]//g;
    if(($what=~m/^$self->{'nickname'}\s*:(.*)/)||($what=~m/!(.*)/)){
        my $request=$1;
        $request=~s/^\s+//;
        my @args=split(/\s+/,$request);
        $self->{'irc_client'}->yield( privmsg => $channel => "reply..." );
    }

}

sub irc_msg {
    my ($self, $sender, $who, $where, $what) = @_[OBJECT, SENDER, ARG0 .. ARG2];
    my $nick = ( split /!/, $who )[0];
    my $channel = $where->[0];
    if ( $what =~m/(.+)/ ) {
        $self->{'irc_client'}->yield( privmsg => $nick => "I don't really do private messages." );
    }
    return;
}

sub irc_ping {
    my $self = $_[OBJECT];
    # do nothing.
    return;
}

1;
