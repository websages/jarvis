package Jarvis::Persona::Watcher;
use AI::MegaHAL;
use POE;
use POSIX qw( setsid );
use POE::Component::Client::Twitter;

sub new {
    my $class = shift;
    my $self = {};
    my $construct = shift if @_;
    $self->{'session_struct'}={};

    # list of required constructor elements
    $self->{'must'} = [ 'alias' ];

    # hash of optional constructor elements (key), and their default (value) if not specified
    $self->{'may'} = {
                       'screenname' => undef,
                       'username'   => undef,
                       'password'   => undef,
                       'retry'      => undef,
                     };

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
                          # special_events go here...
                          $self->{'alias'}.'_update_success'          => 'twitter_update_success',
                          $self->{'alias'}.'_friend_timeline_success' => 'twitter_timeline_success',
                          $self->{'alias'}.'_response_error'          => 'twitter_error',
                          $self->{'alias'}.'_delay_friend_timeline'   => 'delay_friend_timeline',
                        };



    $self->{'cfg'} = {
                       'screenname' => $self->{'screenname'},
                       'username'   => $self->{'username'},
                       'password'   => $self->{'password'},
                       'retry'      => $self->{'retry'},
                      };

    $self->{'twitter'} = POE::Component::Client::Twitter->spawn(%{ $self->{'cfg'} });
    bless($self,$class);
    return $self;
}

sub _start{
     my $self = $_[OBJECT]||shift;
     print STDERR __PACKAGE__ ." start\n";
     $kernel->delay('delay_friend_timeline', 5);
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
         $kernel->post($sender, $respond_event, $who, $where, $self->{'megahal'}->do_reply( $what ));
     }
     return $self->{'alias'};
}

sub delay_friend_timeline {
    my($kernel, $heap) = @_[KERNEL, HEAP];
    $heap->{ $self->alias() }->yield('friend_timeline');
}

sub twitter_update_success {
    my($kernel, $heap, $ret) = @_[KERNEL, HEAP, ARG0];
    print STDERR "twitter_update_success $ret->{text}\n";
    #$heap->{ircd}->yield(daemon_cmd_notice => $conf->{botname}, $conf->{channel}, $ret->{text});
}

sub twitter_timeline_success {
    my($kernel, $heap, $ret) = @_[KERNEL, HEAP, ARG0];
    print STDERR "twitter_update_success $ret\n";
    $kernel->delay('delay_friend_timeline', 5);
}

sub twitter_error {
    my($kernel, $heap, $res) = @_[KERNEL, HEAP, ARG0];
    print STDERR "twitter_update_success $res\n";
    #$heap->{ircd}->yield(daemon_cmd_notice => $conf->{botname}, $conf->{channel}, 'Twitter error');
}

1;
