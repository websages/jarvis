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
             'trace'           => 1,
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
1;
