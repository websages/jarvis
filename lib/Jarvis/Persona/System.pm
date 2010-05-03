package Jarvis::Persona::System;
use AI::MegaHAL;
use POE;
use POSIX qw( setsid );
use POE::Builder;
use LWP::UserAgent;

sub new {
    my $class = shift;
    my $self = {};
    my $construct = shift if @_;
    $self->{'session_struct'}={};

    # list of required constructor elements
    $self->{'must'} = [ 'alias' ];

    # hash of optional constructor elements (key), and their default (value) if not specified
    $self->{'may'} = {
                       'brainpath' => '/dev/shm/brain/system',
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
                          'start'       => 'start',
                          'stop'        => 'stop',
                          'input'       => 'input',
                          'channel_add' => 'channel_add',
                          'channel_del' => 'channel_del',
                          # special_events go here...
                        };


    bless($self,$class);
    return $self;
}

sub start{
    my $self = $_[OBJECT]||shift;
    print STDERR __PACKAGE__ ." start\n";
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
                                          'Path'     => '/dev/shm/brain/system',
                                          'Banner'   => 0,
                                          'Prompt'   => 0,
                                          'Wrap'     => 0,
                                          'AutoSave' => 1
                                        );
    return $self;
}

sub stop{
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
     my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
     # un-wrap the $msg
     my ( $sender_alias, $respond_event, $who, $where, $what, $id ) =
        ( 
          $msg->{'sender_alias'},
          $msg->{'reply_event'},
          $msg->{'conversation'}->{'nick'},
          $msg->{'conversation'}->{'room'},
          $msg->{'conversation'}->{'body'},
          $msg->{'conversation'}->{'id'},
        );

     my $directly_addressed=$msg->{'conversation'}->{'direct'}||0;
     if(defined($what)){
         if(defined($heap->{'locations'}->{$sender_alias}->{$where})){
             foreach my $chan_nick (@{ $heap->{'locations'}->{$sender_alias}->{$where} }){
                 if($what=~m/^\s*$chan_nick\s*:*\s*/){
                     $what=~s/^\s*$chan_nick\s*:*\s*//;
                     $directly_addressed=1;
                 }
             }
         }
         my $r=""; # response
         if($what=~m/^\s*!*help\s*/){
             $r = "I need a help routine.";
         }elsif($what=~m/^\s*!*spawn\s+crunchy/){
             if($directly_addressed == 1){
                 $heap->{'spawned'}->{'crunchy'} = $self->spawn_crunchy();
                 if(defined($heap->{'spawned'}->{'crunchy'})){
                     $r = "crunchy spawned";
                 }else{
                     $r = "something went wrong spawning crunchy";
                 }
             }
         }elsif($what=~m/^\s*!*spawn\s+beta/){
             if($directly_addressed == 1){
                 $heap->{'spawned'}->{'beta'} = $self->spawn_beta();
                 if(defined($heap->{'spawned'}->{'beta'})){
                     $r = "beta spawned";
                 }else{
                     $r = "something went wrong spawning beta";
                 }
             }
         }elsif($what=~m/^\s*!*terminate\s+crunchy/){
             if($directly_addressed == 1){
                  foreach my $sess (@{ $heap->{'spawned'}->{'crunchy'} }){
                      $kernel->post($sess, '_stop');
                  }
              }
              delete $heap->{'spawned'}->{'crunchy'};
              $r = "crunchy terminated";

         }elsif($what=~m/^\s*!*terminate\s+beta/){
             if($directly_addressed == 1){
                  foreach my $sess (@{ $heap->{'spawned'}->{'beta'} }){
                      $kernel->post($sess, '_stop');
                  }
              }
              delete $heap->{'spawned'}->{'beta'};
              $r = "beta terminated";

         }elsif($directly_addressed==1){ 
             if($msg->{'conversation'}->{'direct'} == 0){
                 $r = $who.": ".$self->{'megahal'}->do_reply( $what );
             }else{
                 $r = $self->{'megahal'}->do_reply( $what );
             }
         } # ignore if we didn't match anything.

         # respond
         if($r){
             if($r ne ""){
                     $kernel->post($sender, $respond_event, $msg, $r);
             }
         }





     }
     return $self->{'alias'};
}

sub channel_add{
     # expects a constructor hash of { alias => <sender_alias>, channel => <some_tag>, nick => <nick in channel> }
    my ($self, $kernel, $heap, $construct) = @_[OBJECT, KERNEL, HEAP, ARG0];
         push ( 
                @{ $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} } },
                $construct->{'nick'}
              );
}

sub channel_del{
    # expects a constructor hash of { alias => <sender_alias>, channel => <some_tag>, nick => <nick in channel> }
    my ($self, $kernel, $heap, $construct) = @_[OBJECT, KERNEL, HEAP, ARG0];
    # unshift each of the items in the room, push them back if they're not the one we're removing
    my $count=0;
    my $max = $#{ $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} } };
    while( $count < $max ){
       my $nick = shift(@{ $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} } });
        push( 
              @{ $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} } },
              $nick
            ) unless $nick eq $construct->{'nick'};
        $count++;
   }
    # delete the channel if there are no nicks in it
    if($heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} }){
        if($#{ $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} } } < 0){
            delete $heap->{'locations'}->{ $construct->{'alias'} }->{ $construct->{'channel'} };   
        }
        # delete the alias from locations if there are no channels in it
        if($heap->{'locations'}->{ $construct->{'alias'} }){
            my @channels = keys(%{ $heap->{'locations'}->{ $construct->{'alias'} } });
            if($#channels < 0){ delete $heap->{'locations'}->{ $construct->{'alias'} }; }
        }
    }
}

sub spawn_crunchy{
    my $self=shift;
    #my $persona = shift if @_;
    my $poe = new POE::Builder({ 'debug' => '0','trace' => '0' });
    return undef unless $poe;
    $poe->object_session(
                          new Jarvis::Persona::Crunchy(
                                                        {
                                                          'alias'        => 'crunchy',
                                                          'ldap_domain'  => 'websages.com',
                                                          'ldap_binddn'  => 'uid=crunchy,ou=People,dc=websages,dc=com',
                                                          'ldap_bindpw'  => $ENV{'LDAP_PASSWORD'},
                                                          'twitter_name' => 'capncrunchbot',
                                                          'password'     => $ENV{'TWITTER_PASSWORD'},
                                                          'retry'        => 300,
                                                        }
                                                      )
                        );
    $poe->object_session(
                          new Jarvis::IRC(
                                           {
                                             'alias'        => 'irc_client',
                                             'nickname'     => 'crunchy',
                                             'ircname'      => 'Cap\'n Crunchbot',
                                             'server'       => '127.0.0.1',
                                             'domain'       => 'websages.com',
                                             'channel_list' => [
                                                                 '#soggies',
                                                               ],
                                             'persona'      => 'crunchy',
                                           }
                                         ),
                        );
   return [ 'crunchy', 'irc_client' ];
}

sub spawn_beta{
    my $self=shift;
    #my $persona = shift if @_;
    my $poe = new POE::Builder({ 'debug' => '0','trace' => '1' });
    return undef unless $poe;
    $poe->object_session(
                          new Jarvis::Persona::Crunchy(
                                                        {
                                                          'alias'        => 'beta',
                                                          'ldap_domain'  => 'websages.com',
                                                          'ldap_binddn'  => 'uid=crunchy,ou=People,dc=websages,dc=com',
                                                          'ldap_bindpw'  => $ENV{'LDAP_PASSWORD'},
                                                          'twitter_name' => 'capncrunchbot',
                                                          'password'     => $ENV{'TWITTER_PASSWORD'},
                                                          'retry'        => 300,
                                                        }
                                                      )
                        );

    $poe->object_session(
                          new Jarvis::IRC(
                                           {
                                             'alias'        => 'beta_irc',
                                             'nickname'     => 'beta',
                                             'ircname'      => 'beta Cap\'n Crunchbot',
                                             'server'       => '127.0.0.1',
                                             'domain'       => 'websages.com',
                                             'channel_list' => [
                                                                 '#puppies',
                                                               ],
                                             'persona'      => 'beta',
                                           }
                                         ),
                        );
   return [ 'beta', 'beta_irc' ];
}
1;
