package CMDB::LDAP;
use Net::DNS::Resolver;
use Net::LDAP;
use Data::Dumper;
use YAML;
use strict;

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
    $self->setou("Sets") unless $self->setou;
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
    $self->{'setbase'} = "ou=".$self->{'setou'}.",".$self->basedn;
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
    my $servers;
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
        return undef unless(ref($self->{'ldap'}) eq "Net::LDAP");
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
    my $search_base=shift||$self->{'basedn'};
    $self->ldap_bind unless $self->{'ldap'};
    return undef unless(ref($self->{'ldap'}) eq "Net::LDAP");
    $filter = "(objectclass=*)" unless $filter;
    my $servers;
    chomp($search_base);
    print STDERR "line ". __LINE__ .": searching base: $search_base for ".$filter."\n";
    my $records = $self->{'ldap'}->search(
                                           'base'   => $search_base,
                                           'scope'  => 'sub',
                                           'filter' => $filter,
                                         );
    print STDERR __LINE__ ." ".$records->error."\n" if $records->code;
    my $recs;
    my @entries = $records->entries;
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
    my $entry = shift if @_;
    return undef unless $entry;
    $self->ldap_bind unless $self->{'ldap'};
    my $mesg = $entry->update( $self->{'ldap'} );
    if(($mesg->code == 10) && ($mesg->error eq "Referral received")){
        $self->error("Received referral");
        foreach my $ref (@{ $mesg->{'referral'} }){
            if($ref=~m/(ldap.*:.*)\/.*/){
                 my $new_uri=$1;
                 print STDERR "line ". __LINE__ .": Following referral to: $new_uri\n";
                 my $old_uri = $self->uri;
                 $self->ldap_unbind;              # remove the old binding
                 $self->uri($new_uri);            # update the uri to the referral
                 $self->ldap_bind;                # bind read_write
                 $self->ldap_update( $entry );    # fire this routine off again, (should unbind on return)
                 $self->ldap_unbind;              # remove the write binding
                 $self->ldap_bind;                # bind read_only
                 $self->uri( $old_uri );          # restore the old (read-only) uri for future binds
             }
         }
    }else{
        $mesg->code && $self->error($mesg->code." ".$mesg->error);
    }
    my $errors=$self->error();
    print STDERR __LINE__ ." "."$errors\n" if($errors ne "");
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

sub all_sets{
    my $self = shift;
    my @entries = $self->ldap_search("(objectclass=groupOfUniqueNames)",$self->{'setbase'});
    my $sets;
    foreach my $entry (@entries){
        if(defined($entry)){
            my $entry_dn = $entry->dn;
            # strip the top-level sets ou
            $entry_dn=~s/,ou=$self->{'setou'}.*//;
            $entry_dn = join( ',',( reverse( split(/,/,$entry_dn))));
            $entry_dn=~s/^(ou|cn)=//;         # cns have no identifiers
            $entry_dn=~s/,\s*(cn|ou)=/\//g;
            push(@{ $sets }, $entry_dn);
        }
    }
    return $sets if $sets;
    return [];
}

# things we target:
#   - organizationalUnit: used for organization, disambiguation
#   - groupofUniquenames: used to collect sets of posixAccounts, posixGroups, ipHosts, and other groupofUniquenames
#   - posixAccount      : this should be our user entries (may not be owned or redeployed)
#   - ipHost            : this is a host object (may be owned, redeployed )
# something is either a groupofuniquenames, organizationalunit, ipHost, account
# sets and objects can be owned, ous cannot
# objects may be put in sets or ous
# sets may be put in sets (inheritence) or in Ous

sub is_a{
    my $self = shift;
    my $type;
    return $type;
}

sub sets_in{
    my $self = shift;
    my $parent = shift if @_;
    my @tops;
    if($parent){
        $parent=~s/\/$//;

        $parent=~s/^(cn|ou)=//;
        my $dn = $self->set2dn($parent);
        return undef unless $dn;
        #return the members if it's a cn
        if($dn=~m/^cn/){
            return $self->members($parent);
        }

        # return the sub ou's if not a cn
        foreach my $set (@{ $self->all_sets() }){
            if($set=~m/^${parent}\//){
                $set=~s/^${parent}\///;
                my @tmp = split(/\//, $set );
                my $top = shift( @tmp );
                $top.="/" if $tmp[0];
                push(@tops,$top) unless grep(/$top/,@tops);
            }
        }
    }else{
        foreach my $set (@{ $self->all_sets() }){
            my @tmp = split(/\//, $set );
            my $top = shift( @tmp );
            $top.="\/" if $tmp[0];
            push(@tops,$top) unless grep(/$top/,@tops);
        }
    }
    return @tops;
}

sub sub_sets{
    my $self = shift;
    my $parent = shift if @_;
    my @children;
    foreach my $set (@{ $self->all_sets() }){
        if($set=~m/^$parent/){
            $set=~s/^$parent\:\://;
            $set=~s/\:\:.*//;
            push(@children,$set);
        }
    }
    return @children; 
}

# we lose information converting a dn to a set, so we have to recover it here.
sub set2dn{
    my $self=shift;
    my $set = shift;
    my @set_tree = split(/\//,$set);
    my $cn = pop(@set_tree);
    my $ou_tree;
    if(@set_tree){
        $ou_tree = "ou=".join(",ou=",reverse(@set_tree)).",".$self->{'setbase'};
    }else{
        $ou_tree = $self->{'setbase'};
    }
    chomp(my $old_base = $self->basedn);
    chomp($ou_tree);
    my @entries = $self->ldap_search("objectclass=*",$ou_tree);
    foreach my $entry (@entries){
        return undef unless $entry;
        my $dn = $entry->dn."\n";
        chomp($dn);
        if($dn=~m/^([^=]+=$cn+\s*,\s*$ou_tree)$/i){
            my $dn_actual = $1;
            return $dn_actual;
        }
    }
    return undef;
}

sub dn2set{
    my $self=shift;
    my $dn=shift if @_;
    $dn=~s/,$self->{'setbase'}$//;
    my @tree=split(/,/,$dn);
    my $cn = shift(@tree);
    $cn=~s/^cn=//;
    map { $_=~s/^ou=// } @tree;
    my $set_tree = join('/',reverse(@tree))."/" if(@tree);
    return  $set_tree.$cn;
}

sub baseless{
    my $self=shift;
    my $dn=shift if @_;
    return undef unless $dn;
    chomp($self->{'basedn'});
    $dn=~s/,$self->{'basedn'}$//;
    return $dn;
}

sub dn2simple{
    my $self=shift;
    my $dn=shift if @_;
    $dn=$self->baseless($dn);
    my @tree=split(/,/,$dn);
    my $name = shift(@tree);
    $name=~s/^cn=//;
    $name=~s/^uid=//;
    $name=~tr/A-Z/a-z/;
    map { $_=~s/^ou=// } @tree;
    my $simple_tree = join('/',reverse(@tree))."/" if(@tree);
    $simple_tree=~tr/A-Z/a-z/;
    return $simple_tree.$name;
}

sub entry{
    my $self=shift;
    my $dn = shift if(@_);
    my @dn_parts=split(/,/,$dn);
    my $filter=shift(@dn_parts);
    my $sub_base=join(',',@dn_parts);
    my @entry = $self->ldap_search($filter,$sub_base);
    return @entry;
}

sub members{
    my $self = shift;
    my $set_name = shift if @_;
    my @memberitems;
    foreach my $set (@{ $self->all_sets() }){
        if($set=~m/$set_name$/){  
            my @entry = $self->entry( $self->set2dn($set) );
            my @members = $entry[0]->get_value('uniqueMember');
            foreach my $member (@members){
                my @heiarchy=split(/,/,$member);
                my $item = shift(@heiarchy);
                $item=~s/.*=//;
                push(@memberitems,$item);
            }
        }
    }
    return @memberitems;
}

sub owners{
    my $self = shift;
    my $set_name = shift if @_;
    my @memberitems;
    foreach my $set (@{ $self->all_sets() }){
        if($set=~m/$set_name$/){ 
            my @entry = $self->entry( $self->set2dn($set) );
            my @members = $entry[0]->get_value('owner');
            foreach my $member (@members){
                my @heiarchy=split(/,/,$member);
                my $item = shift(@heiarchy);
                push(@memberitems,$item);
            }
        }
    }
    return @memberitems;
}

sub disown{
    my $self = shift;
    my $user = shift if @_;
    my $target_set = shift if @_;
    return undef unless $user;
    return undef unless $target_set;
    my ($uid,$domain) = split('@',$user);
    my $dn = "uid=$uid,ou=People,dc=".join(',dc=',split(/\./,$domain));
    print STDERR "removing $dn from owners of ". $self->set2dn($target_set)."\n";
    foreach my $set (@{ $self->all_sets() }){
        if($set=~m/^$target_set$/){
            my @entry = $self->entry( $self->set2dn($set) );
            my @owners = $entry[0]->get_value('owner');
            my @newowners=();
            while(my $owner = shift(@owners)){
                push(@newowners,$owner) unless($owner eq $dn);
            }
            $entry[0]->replace( 'owner' => \@newowners );
            $self->ldap_update($entry[0]);
       }
    }
}

sub own{
    my $self = shift;
    my $user = shift if @_;
    my $set = shift if @_;
    return undef unless $user;
    return undef unless $set;
    my ($uid,$domain) = split('@',$user);
    my $dn = "uid=$uid,ou=People,dc=".join(',dc=',split(/\./,$domain));
    print STDERR "making $dn an owner of ". $self->set2dn($set)."\n";
    foreach my $set (@{ $self->all_sets() }){
        if($set=~m/$set$/){  
            my @entry = $self->entry( $self->set2dn($set) );
            my @owners = $entry[0]->get_value('owner');
            push(@owners,$dn) unless grep(/^$dn/,@owners);
            $entry[0]->replace( 'owner' => \@owners );
            $self->ldap_update($entry[0]);
       }
    }
}

# given a short name, return the relative distinguished name for an item.
sub rdn{
    my $self = shift;
    my $fullname = shift if @_;
    my @tree = split('/',$name);
    my $name = pop(@tree);
    return { result => undef, error => "nothing to look up" } unless $name;
    my @entries;

    my @hosts = $self->ldap_search("(cn=$name)","ou=Hosts,".$self->{'basedn'});
    push(@entries,@hosts) if(defined($hosts[0]));
    my @people = $self->ldap_search("(uid=$name)","ou=People,".$self->{'basedn'});
    push(@entries,@people) if(defined($people[0]));
    my @sets = $self->ldap_search("(cn=$name)","ou=Sets,".$self->{'basedn'});
    push(@entries,@sets) if(defined($sets[0]));

    if($#entries < 0){
        return { result => undef, error => "$name not found." };
    }elsif($#entries > 0){ 
        my @choices;
        foreach my $entry (@entries){ 
            my $simple = $self->dn2simple($entry->dn);
            push(@choices, $simple); 
            if($simple eq $fullname){
                return { result => $entry->dn, error => undef };
            }
        }
        return { result => undef, error => "$name too ambiguous: [ ".join(", ",@choices)." ]" };
    }else{
        return { result => $entries[0]->dn, error => undef };
    }
    return undef;
}

#sub share{
#    my $self = shift;
#    my $item = shift if @_;
#    my $set = shift if @_;
##    return undef unless $item;
#    return undef unless $set;
#
#    # get the entry (see if there's only one)
#    # $dn = "cn=$item,ou=Hosts,dc=".join(',dc=',split(/\./,$domain));
#    my @owner_entry = $self->entry( "uid=$item,ou=People,dc=".join(',dc=',split(/\./,$domain)) );
#
#    my ($rdn,$domain) = split('@',$user);
#    print STDERR "making $dn an owner of ". $self->set2dn($set)."\n";
#    foreach my $set (@{ $self->all_sets() }){
#        if($set=~m/$set$/){  
#            my @entry = $self->entry( $self->set2dn($set) );
#            my @owners = $entry[0]->get_value('owner');
#            push(@owners,$dn) unless grep(/^$dn/,@owners);
#            $entry[0]->replace( 'owner' => \@owners );
#            $self->ldap_update($entry[0]);
#       }
#    }
#    return "$item now owns $set";
#}

sub admins{
    my $self = shift;
    my @entry = $self->entry('cn=LDAP Administrators,ou=Special,'.$self->basedn);
    return undef unless $entry[0];
    my @admins;
    foreach my $um ($entry[0]->get_value('uniqueMember')){
        my @dn_parts=split(/,/,$um);
        push(@admins,shift(@dn_parts));
    }
    return @admins;
}

sub is_admin{
    my $self = shift;
    my $user = shift if @_;
    return undef unless $user;
    my ($uid,$domain) = split('@',$user);
    my $dn = "uid=$uid,ou=People,dc=".join(',dc=',split(/\./,$domain));
    my @entry = $self->entry('cn=LDAP Administrators,ou=Special,dc='.join(',dc=',split(/\./,$domain)));
    foreach my $um ($entry[0]->get_value('uniqueMember')){
        if($dn=~m/$um/i){
            return 1;
        }
    }
    return 0;
}

sub add_members{
    my $self=shift;
    my $groupofuniquenames = shift if @_;
    return undef unless $groupofuniquenames;
    my @values;
    my $entries;
    @{ $entries } = $self->get_ldap_entry($groupofuniquenames);
    foreach my $entry (@{ $entries }){
        my $attribute;
        foreach $attribute ( $entry->get_value('uniqueMember') ){
            #push(@values, $attribute);
        }
    }
   return @values;
}

sub del_members{
    my $self=shift;
    my $groupofuniquenames = shift if @_;
    return undef unless $groupofuniquenames;
    my @values;
    my $entries;
    @{ $entries } = $self->get_ldap_entry($groupofuniquenames);
    foreach my $entry (@{ $entries }){
        my $attribute;
        foreach $attribute ( $entry->get_value('uniqueMember') ){
            #push(@values, $attribute);
        }
    }
   return @values;
}

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
