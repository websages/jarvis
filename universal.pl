#!/usr/bin/perl
$ENV{'PATH'}='/usr/local/bin:/usr/bin:/bin';
$ENV{'IFS'}=' \t\n';
################################################################################
# Add local libraries
BEGIN { 
        use Cwd;
        my $path=$0;
        $path=~s/\/[^\/]*$//;
        chdir($path);
        my $libdir=cwd()."/lib";
        my $cpanlib=cwd()."/cpan";
        my $libdirs= [
                       "$cpanlib/lib/perl5/site_perl/5.8.8/i386-linux-thread-multi",
                       "$cpanlib/lib/perl5/5.8.8/i386-linux-thread-multi/",
                       "$cpanlib/lib/perl5/site_perl/5.8.8/",
                       "$cpanlib/lib/perl5/5.8.8/",
                       "$libdir",
                     ];
        # add all of these to our library search path
        foreach my $dir (@{$libdirs}){ unshift @INC, $dir if -d $dir; };
      }
################################################################################
# Include our dependencies
use Data::Dumper;
use Jarvis::IRC;
use Jarvis::Jabber;
#use Jarvis::Persona::Minimal;
#use Jarvis::Persona::MegaHAL;
use Jarvis::Persona::System;
use Jarvis::Persona::Crunchy;
use Jarvis::Persona::Jarvis;
use POE::Builder;
use Sys::Hostname::Long;
use Template;
use Cwd;
################################################################################
sub daemonize {
    defined( my $pid = fork() ) or die "Can't fork: $!\n";
    exit if $pid;
    setsid or die "Can't start a new session: $!\n";
}
################################################################################
$|++;
my $path=$0; $path=~s/\/[^\/]*$//; chdir($path); my $personas=cwd()."persona.d";
# disable jabber if we have no xmpp creds
my $enable_jabber=1;
if(!defined($ENV{'XMPP_PASSWORD'})){
    $enable_jabber=0;
    print STDERR "no XMPP_PASSWORD, disabling XMPP\n";
}

# get a handle for our builder
my $poe = new POE::Builder({ 'debug' => '0','trace' => '0' });
exit unless $poe;
################################################################################
# Template our YAML configs
my ($persona, $irc_connection, $xmpp_connection);
my $config = {
               INCLUDE_PATH => $personas,  # or list ref
               INTERPOLATE  => 1,               # expand "$var" in plain text
               POST_CHOMP   => 1,               # cleanup whitespace 
               PRE_PROCESS  => 'header',        # prefix each template
               EVAL_PERL    => 1,               # evaluate Perl code blocks
             };
my $template = Template->new($config);
################################################################################
# get our fqd, hostname, and domain name
my $fqdn     = hostname_long;
my $hostname = $fqdn;         $hostname=~s/\..*$//;
my $domain   = $fqdn;         $domain=~s/^[^\.]*\.//;
my $vars = {
               'SECRET'        => ${ENV{'SECRET'}},
               'HOSTNAME'      => $hostname,
               'FQDN'          => $fqdn,
               'IRC_SERVER'    => '127.0.0.1',
               'DOMAIN'        => $domain,
               'XMPP_PASSWORD' => ${ENV{'XMPP_PASSWORD'}},
           };
# Set up our sessions 
$template->process('system', $vars, \$persona);              $poe->yaml_sess($persona);
$template->process('system_irc', $vars, \$irc_connection);   $poe->yaml_sess($irc_connection);
$template->process('system_xmpp', $vars, \$xmpp_connection); $poe->yaml_sess($xmpp_connection) if($jabber_enabled == 1);
################################################################################
# fire up the kernel
POE::Kernel->run();

