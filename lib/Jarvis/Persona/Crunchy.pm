package Jarvis::Persona::Crunchy;
use AI::MegaHAL;
use IRCBot::Chatbot::Pirate;
use POE;
use POSIX qw( setsid );

sub new {
    my $class = shift;
    my $self = {};
    my $construct = shift if @_;
    $self->{'session_struct'}={};

    # list of required constructor elements
    $self->{'must'} = [ 'alias' ];

    # hash of optional constructor elements (key), and their default (value) if not specified
    $self->{'may'} = {};

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
    $self->{'states'} = { 
                          $self->{'alias'}.'_start'   => '_start',
                          $self->{'alias'}.'_stop'    => '_stop',
                          $self->{'alias'}.'_input'   => 'input',
                          $self->{'alias'}.'_output'  => 'output',
                          $self->{'alias'}.'_process' => 'process',
                          # special_events go here...
                        };


    bless($self,$class);
    return $self;
}

sub _start{
     my $self = $_[OBJECT]||shift;
     print STDERR __PACKAGE__ ." start\n";
     $self->{'megahal'} = new AI::MegaHAL(
                                           'Path'     => '/usr/lib/share/crunchy',
                                           'Banner'   => 0,
                                           'Prompt'   => 0,
                                           'Wrap'     => 0,
                                           'AutoSave' => 1
                                         );
     return $self;
}

sub _stop{
     my $self = $_[OBJECT]||shift;
     print STDERR __PACKAGE__ ." stop\n";
     return $self;
}

sub states{
     my $self = $_[OBJECT]||shift;
     return $self->{'states'};
}

sub alias{
     my $self = $_[OBJECT]||shift;
     return $self->{'alias'};
}

sub input{
     my ($self, $kernel, $heap, $sender, $who, $where, $what, $respond_event) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
     if(defined($what)){
         # wrap the message into a bundle the process handler expects
         my $message_bundle = {
                                'user'    => $who,
                                'message' => $what,
                                'respond' => { 
                                               'session'   => $sender,
                                               'event'     => $respond_event, 
                                               'specifics' => $where,
                                             },
                              };
         $kernel->post($self->alias(), $self->alias().'_process', $message_bundle );
     }
}

sub output{
     my ($self, $kernel, $heap, $sender, $message_bundle) = @_[OBJECT, KERNEL, HEAP, SENDER, ARGV0];
     # un-wrap the response bundle and send it back to the initiator
     my $who           = $message_bundle->{'user'};
     my $what          = $message_bundle->{'message'};
     my $sender        = $message_bundle->{'respond'}->{'session'};
     my $where         = $message_bundle->{'respond'}->{'specifics'};
     my $respond_event = $message_bundle->{'respond'}->{'event'};
print STDERR Data::Dumper->Dump([$message_bundle]);
     $kernel->post($sender, $respond_event, $who, $where, $what);
}

sub process{
     my ($self, $kernel, $heap, $sender, $message_bundle) = @_[OBJECT, KERNEL, HEAP, SENDER, ARGV0];
print STDERR Data::Dumper->Dump([$message_bundle]);
     my $response = $message_bundle; 
     $response->{'message'} = piratespeak( $self->{'megahal'}->do_reply( $response->{'message'} ) );
     $kernel->post($self->alias(), $self->alias().'_output', $response);
}

1;
