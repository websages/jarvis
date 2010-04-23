package Jarvis::Jabber;
use POE;
sub new   { 
             my $class = shift; 
             my $self = {}; 
             if(defined($construct->{'handle'})){ $self->{'handle'} = $construct->{'handle'}; }
             $self->{'states'} = { 
                                   _start               => '_start',
                                   _stop                => '_stop',
                                   #input_event          => 'input_event',
                                   #error_event          => 'error_event',
                                   #status_event         => 'status_event',
                                   #test_message         => 'test_message',
                                   #output_event         => 'output_event',
                                   #join_channel         => 'join_channel',
                                   #leave_channel        => 'leave_channel',
                                   #send_presence        => 'send_presence',
                                   #presence_subscribe   => 'presence_subscribe',
                                   #approve_subscription => 'approve_subscription',
                                   #refuse_subscription  => 'refuse_subscription',
                                 };
             bless($self,$class); 
             return $self 
           }
sub _start { my $self = $_[OBJECT]; print STDERR ref($self)." start\n"; }
sub _stop  { my $self = $_[OBJECT]; print STDERR ref($self)." stop\n";  }
sub states { my $self = $_[OBJECT]; return $self->{'states'}; }
sub handle { my $self = $_[OBJECT]; return $self->{'handle'};           }

1;
