package Jarvis::Persona::MegaHAL;
use parent Jarvis::Persona::Base;
use AI::MegaHAL;

sub must {
    my $self=shift;
    return [];
}

sub may {
    my $self=shift;
    return {};
}

sub persona_start{
    my $self = $_[OBJECT]||shift;
    if(! -d "/dev/shm/brain"){ mkdir("/dev/shm/brain"); }
    if(! -d "/dev/shm/brain/megahal"){ mkdir("/dev/shm/brain/megahal"); }
    if(! -f "/dev/shm/brain/megahal/megahal.trn"){
        my $agent = LWP::UserAgent->new();
        $agent->agent( 'Mozilla/5.0' );
        my $response = $agent->get("http://github.com/cjg/megahal/raw/master/data/megahal.trn");
        if ( $response->content ne '0' ) {
            my $fh = FileHandle->new("> /dev/shm/brain/megahal/megahal.trn");
            if (defined $fh) {
                print $fh $response->content;
                $fh->close;
            }
        }
    }
    $self->{'megahal'} = new AI::MegaHAL(
                                          'Path'     => '/dev/shm/brain/megahal',
                                          'Banner'   => 0,
                                          'Prompt'   => 0,
                                          'Wrap'     => 0,
                                          'AutoSave' => 1
                                        );
    if($self->{'ldap_enabled'} == 1){
        print STDERR "[ ".$self->error()." ]" if $self->{'ERROR'};
    }
    return $self;
}

sub persona_states{
    my $self = $_[OBJECT]||shift;
    return undef;
}


################################################################################
# Here is what you must provide: 
#   A function named "input_handler" that takes $what and $directly_addressed
#   as arguments, that will regex out the appropriate commands and act on them.
#   It should return a list reference to the list of one-line replies.
#   You will also need to subroutines or inline code to handle these actions.
################################################################################

sub input_handler{
    my $self=shift;
    my $line=shift;
    my $direct=shift||0;
    for ( $line ) {
        /.*/ && return  [ $self->megahal($line) ];
    }
}

sub megahal{
    my $self=shift;
    my $what=shift if @_;
    return  $self->{'megahal'}->do_reply( $what );
}

1;
