         }elsif($what=~m/^!tell\s+(.+?):*\s+(.+?)$/){
             my ($recipient,$message)=($1,$2);
             # first we try to dereference the nickname
             $msg->{'reason'}  = 'tell_request';
             $msg->{'conversation'}->{'originator'} = $msg->{'conversation'}->{'nick'};
             $msg->{'conversation'}->{'nick'}  = $recipient;
             $msg->{'conversation'}->{'body'}  = $message;
             $kernel->post($sender,'authen',$msg);
             my $r = $self->tell($1,$2);
         }elsif($what=~m/^!standings\s*(.*)/){
             my @r = $self->standings();
             $pirate=0;
             foreach $r (@r){
                 $kernel->post($sender, $respond_event, $msg, $r); 
             }
             return; 
         }elsif($what=~m/^!*follow\s+\@(.\S+)/){
             $r = $self->twitter_follow($1,1);
         }elsif($what=~m/^!*unfollow\s+\@(.\S+)/){
             $r = $self->twitter_follow($1,0);
         }elsif($what=~m/^\s*who\s*am\s*i[?\s]*/){
             $pirate=0;
             $msg->{'reason'}='whoami';
             $kernel->post($sender, 'authen', $msg); 
         }elsif($directly_addressed==1){
             if($msg->{'conversation'}->{'direct'} == 0){
                 $r = "$who: ".$self->megahal($what);
             }else{
                 $r = $self->megahal($what);
             }
         }
         
         if($r){ 
             if($r ne ""){ 
                 if( $pirate ){
                     $kernel->post($sender, $respond_event, $msg, piratespeak( $r ) ); 
