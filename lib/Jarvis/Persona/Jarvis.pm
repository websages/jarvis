package Jarvis::Persona::Jarvis;
use parent Jarvis::Persona::Base;
use strict;
use warnings;
use POE; # this is needed even though it's in the parent or we don't send events

sub may {
    my $self=shift;
    return {
             'log_dir'     => '/var/log/irc',
             'ldap_uri'    => 'ldaps//:127.0.0.1:636',
             'ldap_basedn' => "dc=".join(",dc=",split(/\./,`dnsdomainname`)),
             'ldap_binddn' => undef, # anonymous bind by default
             'ldap_bindpw' => undef,
           };
}

sub persona_start{
    my ($self, $kernel, $heap, $sender, $msg) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0];
    $self->{'logger'} = POE::Component::Logger->spawn(
        ConfigFile => Log::Dispatch::Config->configure(
                          Log::Dispatch::Configurator::Hardwired->new(
                              # convert me to yaml and put me in the main config
                              {
                                'file'   => {
                                              'class'    => 'Log::Dispatch::File',
                                              'min_level'=> 'debug',
                                              'filename' => "$self->{'log_dir'}/channel.log",
                                              'mode'     => 'append',
                                              'format'   => '%d{%Y%m%d %H:%M:%S} %m %n',
                                            },
                                'screen' => {
                                               'class'    => 'Log::Dispatch::Screen',
                                               'min_level'=> 'info',
                                               'stderr'   => 0,
                                               'format'   => '%m',
                                            }
                               }
                               )), 'log') or warn "Cannot start Logging $!";
}
################################################################################
# the messages get routed here from the connectors, a reply is formed, and 
# posted back to the sender_alias,reply event (this function will need to be
# overloaded...
################################################################################
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
    my $direct=$msg->{'conversation'}->{'direct'}||0;

    my $nick = undef;
    if(defined($what)){
        if(defined($heap->{'locations'}->{$sender_alias}->{$where})){
            foreach my $chan_nick (@{ $heap->{'locations'}->{$sender_alias}->{$where} }){
                $nick = $chan_nick;
                if($what=~m/^\s*$chan_nick\s*:*\s*/){
                    $what=~s/^\s*$chan_nick\s*:*\s*//;
                    $direct=1;
                }
            }
        }
        my $replies=[];
        ########################################################################
        #                                                                      #
        ########################################################################
        for ( $what ) {
            /^\s*!*help\s*/ && do { $replies = [ "i need a help routine" ] if($direct); last; };
            /^\s*good morning $nick\s*/ && do { $replies = [ "good morning $who" ]; last; };
            /.*/            && do { $replies = [ "i don't understand"    ] if($direct); last; };
            /.*/            && do { last; }
        }
        ########################################################################
        #                                                                      #
        ########################################################################
        if($direct==1){ 
            foreach my $line (@{ $replies }){
                if( defined($line) && ($line ne "") ){ 
                   if(ref($where) eq 'ARRAY'){  # this was an irc privmsg
                       $where = $where->[0];
                       $kernel->post($sender, $respond_event, $msg, $line); 
                   }else{
                       $kernel->post($sender, $respond_event, $msg, $who.': '.$line); 
                   }
                   $kernel->post($self->{'logger'}, 'log', "#privmsg[$where] <$who> $what");
                   $kernel->post($self->{'logger'}, 'log', "#privmsg[$who] <$where> $line");
               }else{
                   $kernel->post($self->{'logger'}, 'log', "$where <$nick> $who: $line");
               }
            }
        }else{
            foreach my $line (@{ $replies }){
                if( defined($line) && ($line ne "") ){ 
                    $kernel->post($sender, $respond_event, $msg, $line); 
                    $kernel->post($self->{'logger'}, 'log', "$where <$nick> $line");
                }
            }
        }
    }
    return $self->{'alias'};
}

1;
