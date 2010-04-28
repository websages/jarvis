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
                          $self->{'alias'}.'_tweet'   => 'new_tweet',
                          # special_events go here...
                          $self->{'alias'}.'_update_success'         => 'twitter_update_success',
                          $self->{'alias'}.'_delay_friend_timeline'  => 'delay_friend_timeline',
                          'twitter.friend_timeline_success'          => 'twitter_timeline_success',
                          'twitter.response_error'                   => 'twitter_error',
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
     my $kernel = $_[KERNEL];
     print STDERR __PACKAGE__ ." start\n";
     $self->{'twitter'}->yield('register');
     $kernel->yield($self->alias().'_tweet', "yarr. restarted me mateys...");
     $kernel->delay($self->alias().'_delay_friend_timeline', 5);
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
     #if(defined($what)){
     #    $kernel->post($sender, $respond_event, $who, $where, $self->{'megahal'}->do_reply( $what ));
     #}
     return $self->{'alias'};
}

sub delay_friend_timeline {
    my($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
    $heap->{ $self->alias() }->{'twitter'}->yield('friend_timeline');
}

sub new_tweet {
    my($self, $kernel, $heap, $status) = @_[OBJECT, KERNEL, HEAP, ARGV0];
    $heap->{ $self->alias() }->{'twitter'}->yield('update', $status);
}

sub twitter_update_success {
    my($self, $kernel, $heap, $ret) = @_[OBJECT, KERNEL, HEAP, ARG0];
    print STDERR "twitter_update_success\n". ref($ret) ."\n";
    #$heap->{ircd}->yield(daemon_cmd_notice => $conf->{botname}, $conf->{channel}, $ret->{text});
}

sub twitter_timeline_success {
    my($self, $kernel, $heap, $ret) = @_[OBJECT, KERNEL, HEAP, ARG0];
    my $count=0;
    foreach my $tweet (@{ $ret }){
        #print "[\@". join("\n",keys(%{$tweet->{'user'}->{'screen_name}})) ."]: ".$tweet->{'text'}." ";
        my $text=$tweet->{'text'};
        if($tweet->{'user'}->{'screen_name'} eq 'mediacas'){
            $text=~s/^I used #*Shazam to discover\s+(.*)\s+by\s+(.*)\s+http:\/\/.*/$1 $2/;
            $text=~s/^I used #*Shazam to discover\s+(.*)\s+by\s+(.*)\s+#shazam.*/$1 $2/;
        }
        print $count++. "[\@".$tweet->{'user'}->{'screen_name'}."($tweet->{'id'})]: ".$text." ";
        print "\n";
        # print join("|", keys(%{ $tweet->{'user'} }))."\n";
        # friends_count
        # profile_background_tile
        # profile_image_url
        # contributors_enabled
        # profile_sidebar_fill_color
        # profile_link_color
        # profile_sidebar_border_color
        # created_at
        # utc_offset
        # profile_background_color
        # notifications
        # url
        # id
        # verified
        # following
        # profile_background_image_url
        # screen_name
        # location
        # lang
        # followers_count
        # name
        # protected
        # statuses_count
        # description
        # profile_text_color
        # time_zone
        # geo_enabled
        # favourites_count

        # print join("|", keys(%{ $tweet }))."\n";
        # source
        # favorited
        # geo
        # coordinates
        # place
        # truncated
        # created_at
        # contributors
        # text
        # in_reply_to_user_id
        # user
        # id
        # in_reply_to_status_id
        # in_reply_to_screen_name
    }
    $kernel->delay($self->alias().'_delay_friend_timeline', $self->{'retry'});
}

sub twitter_error {
    my($self, $kernel, $heap, $res) = @_[OBJECT, KERNEL, HEAP, ARG0];
    print STDERR "twitter_error\n". Data::Dumper->Dump([$res->{'_rc'}, $res->{'_content'}]) ."\n";
    #$heap->{ircd}->yield(daemon_cmd_notice => $conf->{botname}, $conf->{channel}, 'Twitter error');
}

1;
