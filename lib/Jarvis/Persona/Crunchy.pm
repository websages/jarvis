package Jarvis::Persona::Crunchy;
use AI::MegaHAL;
use IRCBot::Chatbot::Pirate;
use POE;
use POSIX qw( setsid );
use Net::LDAP;
use Net::DNS;
use strict;
use warnings;

sub new {
    my $class = shift;
    my $self = {};
    my $construct = shift if @_;
    $self->{'session_struct'}={};

    # list of required constructor elements
    $self->{'must'} = [ 'alias' ];

    # hash of optional constructor elements (key), and their default (value) if not specified
    $self->{'may'} = {
                       'ldap_domain' => undef,
                       'ldap_binddn' => undef,
                       'ldap_bindpw' => undef,
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
                        };
    if( (!defined($self->{'ldap_domain'})) || (!defined($self->{'ldap_binddn'})) || (!defined($self->{'ldap_bindpw'})) ){
        print STDERR "[ $self->{'ldap_domain'} :: $self->{'ldap_binddn'} :: $self->{'ldap_bindpw'} ]\n";
        print STDERR "WARNING: Not enough LDAP paramaters supplied. LDAP operations will be disabled.\n";
        $self->{'ldap_enabled'}=0;
    }else{
        $self->{'ldap_basedn'} = $self->{'ldap_domain'};
        $self->{'ldap_basedn'} =~s/\./,dc=/g;
        $self->{'ldap_basedn'} = "dc=".$self->{'ldap_basedn'};
        $self->{'resolver'} = Net::DNS::Resolver->new;
        my $srv = $self->{'resolver'}->query( "_ldap._tcp.".$self->{'ldap_domain'}, "SRV" );
        if($srv){
            foreach my $rr (grep { $_->type eq 'SRV' } $srv->answer) {
                my $uri;
                my $order=$rr->priority.".".$rr->weight;
                if($rr->port eq 389){
                    $uri = "ldap://".$rr->target.":".$rr->port;
                }else{
                    $uri = "ldaps://".$rr->target.":".$rr->port;
                }
                if(defined($self->{'ldap_uri'}){ 
                    $self->{'ldap_uri'}=$self->{'ldap_uri'}." ,$uri";
                }else{
                    $self->{'ldap_uri'}=$self->{'ldap_uri'};
                }
                $self->{'ldap_enabled'}=1;
            }
        }else{
            print STDERR "Cannot resolve srv records for _ldap._tcp.".$self->{'ldap_domain'}.". LDAP operations will be disabled.\n";
            $self->{'ldap_enabled'}=0;
        }
        print STDERR "$self->{'ldap_uri'}\n";
    }

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
         my $r=""; # response
         if($what=~m/^\s*fortune\s*$/){
             $r = $self->fortune();
         }elsif($what=~m/^\s*crunchy\s*:*\s*/){
             $r = $self->megahal();
         }
         
         # respond in pirate if we have something to say...
         if($r ne ""){ $kernel->post($sender, $respond_event, $who, $where, piratespeak( $r ) ); }
     }
}

sub megahal{
    my $self=shift;
    my $what=shift if @_;
    return  $self->{'megahal'}->do_reply( $what );
}

sub fortune{
    my $self=shift;
    return  qx( /usr/games/fortune -s );
}
################################################################################
# Begin LDAP events
################################################################################

################################################################################
# End LDAP events
################################################################################

1;
