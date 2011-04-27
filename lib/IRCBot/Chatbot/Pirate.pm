package IRCBot::Chatbot::Pirate;

use strict;
use warnings;

require Exporter;

our @ISA     = qw(Exporter);
our @EXPORT  = qw(piratespeak);
our $VERSION = '0.01';

# Entire words only
my %map = (
    'is'        => 'be',            'big'       => 'vast',
    'friend'    => 'matey',         'my'        => 'me',
    'say'       => 'cry',           'small'     => 'puny',
    'isn\'t'    => 'be not',        'the'       => 'tha',
    'are'       => 'be',            'to'        => 't\'',
    'of'        => 'o\'',           'am'        => 'be',
    'you'       => 'ya',            'yes'       => 'aye',
    'no'        => 'nay',           'never'     => 'nary',
    'i\'m'      => 'i be',          'you\'re'   => 'you be',
    'girl'      => 'lass',          'woman'     => 'wench',
    'hello'     => 'ahoy',          'beer'      => 'grog',
    'quickly'   => 'smartly',       'do'        => 'd\'',
    'your'      => 'yer',           'for'       => 'fer',
    'go'        => 'sail',          'we'        => 'our jolly crew',
    'and'       => 'n\'',           'good'      => 'jolly good',
    'yeah'      => 'aye',           'that\'s'   => 'that be',
    'over'      => 'o\'er',         'yah'       => 'aye',
    'hand'      => 'hook',          'leg'       => 'peg',
    'eye'       => 'eye-patch',     'flag'      => 'jolly roger',
    'dick'      => 'plank',         'penis'     => 'plank',
    'fuck'      => 'curse',         'shit'      => 'shite',
    'treasure'  => 'booty',         'butt'      => 'booty',
    'really'	=> 'verily',        'leg'       => 'peg',
    'them'      => '\'em',          'house'     => 'shanty',
    'home'      => 'shanty',        'quickly'   => 'smartly',
);

# Pirate filler
my @fill = (
    'avast',                        'splice the mainbrace',
    'shiver me timbers',            'ahoy',
    'arrrrr',                       'arrgh',
    'yo ho ho',                     'yarrr',
    'eh',                           'arrrghhh',
    'where\'s me rum?',             'walk tha plank',
    'arrr',                         'ahoy matey',
    'surrender yer booty',
);

# Punctuation
my @punct = ( '!', '.', '!!');

sub piratespeak {
    my ($sentence) = @_;
    my @words = split / /, $sentence;
    map { $map{$_} && do { $_ = $map{$_} }; $_ =~ s/ing/in'/; } @words;
    $sentence = join ' ', @words;

    if (int rand 5 == 1) { $sentence = $fill[rand $#fill] . $punct[rand $#punct] . " $sentence"; }
    if (int rand 5 == 1) { $sentence = "$sentence " . $fill[rand $#fill] . $punct[rand $#punct]; }

    return $sentence;
}

1;
