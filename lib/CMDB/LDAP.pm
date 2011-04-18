package CMDB::LDAP;
use Net::DNS::Resolver;
use Net::LDAP;
use Data::Dumper;
use YAML;

################################################################################
# any of the following constructors should work:
# The more specific the constructor, the fewer assumptions will be made.
# They will be tried in this order until the first hash is populated for all values
# subsequent or redundant data will be ignored
#
# { 
#   'uri'     => 'ldaps://ldap.example.org:636',
#   'basedn'  => 'dc=example,dc=org',
#   'binddn'  => 'uid=whitejs,ou=People,dc=example,dc=org',
#   'bindpw'  => 'MyP@ssw0rd123!',
#   'setsou' => 'Sets', <- ou=Sets,${basedn} (defaults to 'Sets' if not specified)
# }
#
# { 
#    'domain'   => 'example.org'       <- basedn derived from domain, uri from SRV records
#    'uid'      => 'whitejs,           <- binddn assumed to be uid
#    'bindou'   => 'People'            <- assumed People if not provided
#    'password' => 'MyP@ssw0rd123!', 
# } 
#
# { 
#    'uid'      => 'whitejs@example.org', <- domain from RHS of @, then as above
#    'password' => 'MyP@ssw0rd123!'         
# }
#
# { 
#    'uid'      => 'whitejs',             <- domain from `dnsdomainname`, then as above 
#    'password' => 'MyP@ssw0rd123!' 
# }
#
# { 
#    creds =>'whitejs@example.org:MyP@ssw0rd123!'  <- split /:/, then as above
# }
# 
# { 
#    creds =>'whitejs:MyP@ssw0rd123!'     <- split /:/, then as above
# }
# 
# {}  <-- bind anonymously using `domainname` and SRV records
#
# undef <- $ENV {'URI', 'BINDDN', 'BINDPW', 'BASEDN'} (env should override ldap.conf)  FIXME TODO
#          or (failing that) populated from ldaprc/.ldaprc/ldap.conf ( ldap.conf(5) )  FIXME TODO
#          or (failing those) `dnsdomain`, SRV records, anon_bind                      FIXME TODO
#
# basically the only way it's not going to bind is if you're just not trying...
################################################################################

sub new{
    my $class = shift;
    my $cnstr = shift if @_;
    my $self = {};
    bless($self,$class);
    ############################################################################
    #
    $self->uri($cnstr->{'uri'})       if $cnstr->{'uri'};
    $self->basedn($cnstr->{'basedn'}) if $cnstr->{'basedn'};
    $self->binddn($cnstr->{'binddn'}) if $cnstr->{'binddn'};
    $self->bindpw($cnstr->{'bindpw'}) if $cnstr->{'bindpw'};
    $self->domain($cnstr->{'domain'}) if $cnstr->{'domain'};
    $self->setou($cnstr->{'setou'})   if $cnstr->{'setou'};
    ############################################################################
    # determine the domain any way possible
    my $domain;
    if( ! $self->domain ){
        $self->domain($self->basedn2domain($self->basedn)) if $self->basedn();
    }
    if( ! $self->domain ){
        if( $cnstr->{'uid'} ){
            if($cnstr->{'uid'}=~m/([^@]*)@([^@]*)/){
               $self->domain($2);
            }
        }
    }
    if( ! $self->domain ){
        my $old_path=$ENV{'PATH'};
        $ENV{'PATH'}="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin";
        open(my $domainname,"domainname|");
        chomp($domain=<$domainname>);
        close($domainname);
        $ENV{'PATH'}=$old_path;
        $self->domain($domain) if($domain=~m/\./);
    }
    if( ! $self->domain ){
        my $old_path=$ENV{'PATH'};
        $ENV{'PATH'}="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin";
        open(my $dnsdomainname,"dnsdomainname|");
        chomp($domain=<$dnsdomainname>);
        close($dnsdomainname);
        $ENV{'PATH'}=$old_path;
        $self->domain($domain) if($domain=~m/\./);
    }

    ############################################################################
    # determine the uri any way possible
    unless($self->uri){
        if( $self->domain ){
            $self->uri($self->domain2uri($self->domain));
        }
    }

    ############################################################################
    # determine the basedn any way possible
    unless($self->basedn){
        if( $self->domain ){
            $self->basedn($self->domain2basedn($self->domain));
        }
    }

    ############################################################################
    # determine the binddn andy way possible
    unless($self->binddn){
        my $uid;
        if( $cnstr->{'uid'} ){
            if($cnstr->{'uid'}=~m/^([^@\:]*)/){
               $uid=$1;
            }
        }
        my $ou = $cnstr->{'ou'}||"People";
        $self->binddn("uid=$uid,ou=$ou,".$self->basedn) if $uid;
    }
    unless($self->binddn){
        my $uid;
        if( $cnstr->{'creds'} ){
            if($cnstr->{'creds'}=~m/^([^@\:]*)/){
               $uid=$1;
            }
        }
        my $ou = $cnstr->{'ou'}||"People";
        $self->binddn("uid=$uid,ou=$ou,".$self->basedn) if $uid;
    }

    ############################################################################
    # determine the bindpw andy way possible
    unless($self->bindpw){
        $self->bindpw($cnstr->{'password'}) if $cnstr->{'password'};
    }
    unless($self->bindpw){
        my $bindpw;
        if( $cnstr->{'uid'} ){
            if($cnstr->{'uid'}=~m/^([^@\:]*):(.*)/){
               $bindpw=$2;
            }
        }
        $self->bindpw($bindpw) if $bindpw;
    }
    unless($self->bindpw){
        my $bindpw;
        if( $cnstr->{'creds'} ){
            if($cnstr->{'creds'}=~m/^([^:]*):(.*)/){
               $bindpw=$2;
            }
        }
        $self->bindpw($bindpw) if $bindpw;
    }

    return $self;
}

sub domain{
    # # should changing the domain changes the basedn, binddn, and uri?
    my $self = shift;
    #my $previous = $self->{'domain'};
    $self->{'domain'} = shift if @_;
    #if($previous ne $self->{'domain'} ){
    #    $self->basedn($self->domain2basedn($self->{'domain'});
    #}
    return $self->{'domain'} if $self->{'domain'};
    return undef;
}

sub uri{
    my $self = shift;
    $self->{'uri'} = shift if @_;
    return $self->{'uri'} if $self->{'uri'};
    return undef;
}

sub basedn{
    my $self = shift;
    $self->{'basedn'} = shift if @_;
    return $self->{'basedn'} if $self->{'basedn'};
    return undef;
}

sub binddn{
    my $self = shift;
    $self->{'binddn'} = shift if @_;
    return $self->{'binddn'} if $self->{'binddn'};
    return undef;
}

sub bindpw{
    my $self = shift;
    $self->{'bindpw'} = shift if @_;
    return $self->{'bindpw'} if $self->{'bindpw'};
    return undef;
}

sub setou{
    my $self = shift;
    $self->{'setou'} = shift if @_;
    return $self->{'setou'} if $self->{'setou'};
    return undef;
}

sub bind_data{
    my $self = shift;
    return {
             'uri'    => $self->uri,
             'basedn' => $self->basedn,
             'binddn' => $self->binddn,
             'bindpw' => $self->bindpw,
           };
}

sub domain2basedn{
    my $self = shift;
    my $domain = shift if @_;
    return undef unless $domain;
    return "dc=".join(',dc=',split(/\./,$domain));
}

sub basedn2domain{
   my $self = shift;
   my $basedn = shift if @_;
   return undef unless $basedn;
   $basedn=~s/^dc=//;
   return join("\.",split(/,dc=/,$basedn));
   
}

sub domain2uri{
    my $self=shift;
    my $domain = shift;
    return undef unless $domain;
    $self->{'resolver'} = Net::DNS::Resolver->new;
    my $srv = $self->{'resolver'}->query( '_ldap._tcp.'.$domain, "SRV" );
    if($srv){
        my $scale;
        foreach my $rr (grep { $_->type eq 'SRV' } $srv->answer) {
            my $uri;
            my $order = $rr->priority.".".$rr->weight;
            if($rr->port eq 389){
                $uri = "ldap://".$rr->target.":".$rr->port;
            }else{
                $uri = "ldaps://".$rr->target.":".$rr->port;
            }
            push(@{ $scale->{$rr->priority}->{$rr->weight} }, $uri);
        }
        foreach my $priority (sort(keys(%{$scale}))){
            foreach my $weight (reverse(sort(keys(%{ $scale->{$priority} })))){
                foreach my $uri (@{ $scale->{$priority}->{$weight} }){
                    if( defined($self->{'uri'}) ){
                        $self->{'uri'}=$self->{'uri'}.", $uri";
                    }else{
                        $self->{'uri'}=$uri;
                    }
                }
            }
        }
    }else{
        print STDERR "Cannot resolve SRV records for _ldap._tcp.$domain\n";
        return undef;
    }
    return $self->{'uri'};
}

sub error{
    my $self=shift;
    if(@_){
        push(@{ $self->{'ERROR'} }, @_);
    }
    if($#{ $self->{'ERROR'} } >= 0 ){
        return join("\n",@{ $self->{'ERROR'} });
    }
    return '';
}
#
# End constructor validation work
################################################################################

################################################################################
# Begin actual LDAP work
# 

sub ldap_bind{
    my $self = shift;
    # change self->uri if you need to change servers
    if($self->{'uri'}){
        @{ $servers }= split(/\,\s+/,$self->{'uri'})
    }
    my $mesg;
    # loop through the servers in
    while( my $server = shift(@{ $servers })){
        if($server=~m/(.*)/){
            $server=$1 if ($server=~m/(^[A-Za-z0-9\-\.\/:]+$)/);
        }
        $self->{'ldap'} = Net::LDAP->new($server) || warn "could not connect to $server $@";
        if(defined($self->binddn) && defined($self->bindpw)){
            $mesg = $self->{'ldap'}->bind( $self->binddn, password => $self->bindpw );
        }else{
            $mesg = $self->{'ldap'}->bind( );
        }
        if($mesg->code != 0){ $self->error($server." : ".$mesg->error); }
        last unless $mesg->code; # move to the next uri if there was an error
    }
    return undef unless $self->{'ldap'};
    return $self;
}

sub ldap_unbind{
    my $self = shift;
    $self->{'ldap'}->unbind();
    return $self;
}

sub ldap_search {
    my $self = shift;
    my $filter = shift if @_;
    $self->ldap_bind unless $self->{'ldap'};
    $filter = "(objectclass=*)" unless $filter;
    my $servers;
    my $records = $self->{'ldap'}->search(
                                           'base'   => "$self->{'basedn'}",
                                           'scope'  => 'sub',
                                           'filter' => $filter
                                         );
    unless($records->{'resultCode'}){
       $self->error($records->{'resultCode'}) if $records->{'resultCode'};
    }
    my $recs;
    my @entries = $records->entries;
    $self->{'ldap'}->unbind();
    print STDERR "$#entries\n";
    return @entries if @entries;
    return undef;
}

sub ldap_add{
    my $self = shift;
    my $entry = shift if @_;
    return undef unless $entry;
    $self->ldap_update($entry->add);
    return $self;
}

sub ldap_update{
    my $self = shift;
    my $entry = $shift if@_;
    return undef unless $entry;
    $self->ldap_bind unless $self->{'ldap'};
    my $mesg = $entry->update( $self->{'ldap'} );
    if(($mesg->code == 10) && ($mesg->error eq "Referral received")){
        $self->error("Received referral");
        foreach my $ref (@{ $mesg->{'referral'} }){
            if($ref=~m/(ldap.*:.*)\/.*/){
                 my $old_uri = $self->uri;
                 $self->unbind;                   # remove the old binding
                 $self->uri($ref);                # update the uri to the referral
                 $self->ldap_update( $entry );    # fire this routine off again, (should unbind on return)
                 $self->uri( $old_uri );          # restore the old (read-only) uri for future binds
             }
         }
    }else{
        $mesg->code && $self->error($mesg->code." ".$mesg->error);
    }
    my $errors=$self->error();
    print STDERR "$errors\n" if($errors ne "");
    $self->ldap_unbind if $self->{'ldap'};
    return $self;
}

sub ldap_delete{
    my $self = shift;
    my $entry = shift if @_;
    return undef unless $entry;
    $self->ldap_update($entry->delete);
    return $self;
}

################################################################################
# abstractions for LDAP below here
#

sub unique_members{
    my $self = shift;
    my $groupofuniquenames = shift if @_;
    return undef unless $groupofuniquenames;
    my @values;
    my $entries;
    @{ $entries } = $self->get_ldap_entry($groupofuniquenames);
    foreach my $entry (@{ $entries }){
        my $attribute;
        foreach $attribute ( $entry->get_value('uniqueMember') ){
            push(@values, $attribute);
        }
    }
   return @values;
}

sub entry_attr{
    my $self = shift;
    my $entrydn = shift if @_;
    my $attr = shift if @_;
    return undef unless $entrydn;
    return undef unless $attr;
    my @values;
    my $entries;
    @{ $entries } = $self->get_ldap_entry($entrydn);
    foreach my $entry (@{ $entries }){
        my $attribute;
        foreach $attribute ( $entry->get_value($attr) ){
            push(@values, $attribute);
        }
    }
   return @values;
}

1;