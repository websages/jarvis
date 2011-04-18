package Jarvis::Persona::Jarvis;
use parent Jarvis::Persona::Base;

################################################################################
# Jarvis is Just A Really Vigilant Infrastructure Sysadmin.
# most of what he does will be done with an alarm() or delay()
################################################################################
sub may {
    my $self = shift;
    return { 
             'ldap_uri'        => undef,
             'ldap_binddn'     => undef,
             'ldap_bindpw'     => undef,
             'log_dir'         => '/var/log/irc',
           };
}

sub persona_start{
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    if(-d "/var/log/irc"){    $self->{'logdir'} = "/var/log/irc"    unless $self->{'logdir'}; }
    if(-d "/var/log/irclog"){ $self->{'logdir'} = "/var/log/irclog" unless $self->{'logdir'}; }
    if($self->{'logdir'}){
        $self->{'logger'}  = POE::Component::Logger->spawn(
                                 ConfigFile => Log::Dispatch::Config->configure(
                                     Log::Dispatch::Configurator::Hardwired->new(
                                         # convert me to yaml and put me in the main config
                                         {
                                           'file'   => {
                                                         'class'    => 'Log::Dispatch::File',
                                                         'min_level'=> 'debug',
                                                         'filename' => "$self->{'logdir'}/channel.log",
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
    return $self;
}

sub stop{
    my ($self, $kernel, $heap, $sender, @args) = @_[OBJECT, KERNEL, HEAP, SENDER, ARG0 .. $#_];
    return $self;
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
    print STDERR Data::Dumper->Dump([ $self->{'logger'} ]);
    $heap->{ $self->alias() }->{'logger'}->yield("$where <$who> $what");
    my $direct=$msg->{'conversation'}->{'direct'}||0;
    if(defined($what)){
        if(defined($heap->{'locations'}->{$sender_alias}->{$where})){
            foreach my $chan_nick (@{ $heap->{'locations'}->{$sender_alias}->{$where} }){
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
            /^\s*!*help(.*)/      && return $self->help($1);
            /^\s*!*spawn(.*)/     && return $self->spawn($1)     if $direct;
            /^\s*!*terminate(.*)/ && return $self->terminate($1) if $direct;
            /.*/                  && return  [];        # say nothing by default
        }
        ########################################################################
        #                                                                      #
        ########################################################################
        if($direct==1){
            foreach my $line (@{ $replies }){
                if($msg->{'conversation'}->{'direct'} == 0){
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $who.': '.$line); }
                }else{
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $line); }
                }
            }
        }else{
            foreach my $line (@{ $replies }){
                    if( defined($line) && ($line ne "") ){ $kernel->post($sender, $respond_event, $msg, $line); }
            }
        }
    }
    return $self->{'alias'};
}


sub help(){
    my $self=shift;
    my $topic=shift if @_;
    $topic=~s/^\s+//;
    return  [ "commands: help spawn terminate" ];
}

sub spawn(){
    my $self=shift;
    my $target=shift if @_;
    $target=~s/^\s+// if $target;
    return  [ "I need a spawn routine" ];
}

sub terminate(){
    my $self=shift;
    my $target=shift if @_;
    $target=~s/^\s+// if $target;
    return  [ "I need a terminate routine" ];
}

1;
