package Jarvis::Persona::System;
use parent Jarvis::Persona::Base;
use AI::MegaHAL;
use POE;
use POSIX qw( setsid );
use POE::Builder;
use LWP::UserAgent;

sub must {
    my $self = shift;
    return  [ ];
}

sub may {
    my $self = shift;
    return  { 'brainpath' => '/dev/shm/brain/system' };
}

sub persona_start{
    my $self=shift;
    my @brainpath = split('/',$self->{'brainpath'}); 
    shift(@brainpath); # remove the null in [0]
    # mkdir -p
    my $bpath="";
    while(my $append = shift(@brainpath)){
        $bpath = $bpath.'/'.$append;
        if(! -d $bpath ){ mkdir($bpath); }
    }
    if(! -f $self->{'brainpath'}."/megahal.trn"){ 
        my $agent = LWP::UserAgent->new();
        $agent->agent( 'Mozilla/5.0' );
        my $response = $agent->get("http://github.com/cjg/megahal/raw/master/data/megahal.trn");
        if ( $response->content ne '0' ) {
            my $fh = FileHandle->new("> $self->{'brainpath'}/megahal.trn");
            if (defined $fh) {
                print $fh $response->content;
                $fh->close;
            }
        }
    }
    $self->{'megahal'} = new AI::MegaHAL(
                                          'Path'     => $self->{'brainpath'},
                                          'Banner'   => 0,
                                          'Prompt'   => 0,
                                          'Wrap'     => 0,
                                          'AutoSave' => 1
                                        );
    return $self;
}



sub spawn_crunchy{
    my $self=shift;
    #my $persona = shift if @_;
    my $poe = new POE::Builder({ 'debug' => '0','trace' => '0' });
    return undef unless $poe;
    $poe->yaml_sess(<<"    ...");
    ---
    class: Jarvis::Persona::Crunchy
    init:
      alias: crunchy
      ldap_domain: websages.com
      ldap_binddn: uid=crunchy,ou=People,dc=websages,dc=com
      ldap_bindpw: ${ENV{'LDAP_PASSWORD'}}
      twitter_name: capncrunchbot
      password: ${ENV{'TWITTER_PASSWORD'}}
      retry: 300
    ...
    $poe->yaml_sess(<<"    ...");
    ---
    class: Jarvis::IRC
    init:
      alias: irc_client
      nickname: crunchy
      ircname: Cap'n Crunchbot
      server: 127.0.0.1
      domain: websages.com
      channel_list:
        - #soggies
      persona: crunchy
    ...
    return [ 'crunchy', 'irc_client' ];
}

sub spawn_beta{
    my $self=shift;
    #my $persona = shift if @_;
    my $poe = new POE::Builder({ 'debug' => '0','trace' => '1' });
    return undef unless $poe;
    $poe->yaml_sess(<<"    ...");
    ---
    class: Jarvis::Persona::Crunchy
    init:
      alias: beta
      ldap_domain: websages.com
      ldap_binddn: uid=crunchy,ou=People,dc=websages,dc=com
      ldap_bindpw: ${ENV{'LDAP_PASSWORD'}}
      twitter_name: capncrunchbot
      password: ${ENV{'TWITTER_PASSWORD'}}
      retry: 300
    ...
    $poe->yaml_sess(<<"    ...");
    class: Jarvis::IRC
    init:
      alias: beta_irc
      nickname: beta
      ircname: beta Cap'n Crunchbot
      server: 127.0.0.1
      domain: websages.com
      channel_list:
        - #puppies
      persona: beta
    ...
    return [ 'beta', 'beta_irc' ];
}
1;
