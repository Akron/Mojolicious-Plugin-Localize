#!usr/bin/env perl
use Mojolicious::Lite;
use Mojolicious::Commands;
use Data::Dumper;
use Test::Output qw/:stdout :stderr :functions/;
use Test::More;
use Test::Mojo;
use lib '../lib';

my $t = Test::Mojo->new;
my $app = $t->app;

$ENV{MOJO_LOCALIZE_DEBUG} = 1;

use_ok('Mojolicious::Plugin::Localize::Command::dictionary');
my $dict = Mojolicious::Plugin::Localize::Command::dictionary->new;
$dict->app($app);

is($dict->usage, '', 'Usage');

$app->plugin('Localize' => {
  dict => {
    welcome => {
      _ => sub { $_->locale },
      en => 'Welcome!',
      de => 'Willkommen!'
    },
    thankyou => {
      _ => sub { $_->locale },
      en => 'Thank you!',
      de => 'Danke!',
      fr => 'Merci!'
    },
    _ => sub { $_->locale },
    de => {
      bye => 'Auf Wiedersehen!',
      user => {
        _ => sub { [qw/technical communitiy/] },
        technical => 'Nutzer',
        community => 'Mitglied'
      }
    },
    en => {
      bye => 'Good bye!'
    },
    fr => {
      hello => 'Bonjour!'
    }
  }
});

is_deeply(
  $app->commands->namespaces,
  [qw/Mojolicious::Command Mojolicious::Plugin::Localize::Command/],
  'Namespaces'
);
my $cmds = $app->commands;

stdout_like(
  sub {
    local $ENV{HARNESS_ACTIVE} = 0;
    $cmds->run;
  },
  qr/dictionary/,
  'Show generate'
);

# {
#   # welcome_fr => 'Welcome!',
#   # fr_bye => 'Good bye',
#   # # fr_user_technical => '',
#   # # fr_user_community => ''
# }

my $template = stdout_from(
  sub {
    local $ENV{HARNESS_ACTIVE} = 0;

    # Get a template for french based on the english dictionary
    $cmds->run('dictionary', 'en', 'fr');
  }
);

like($template, qr/\"welcome_fr\"\s*=\>\s*\\\"Welcome!\"/, 'welcome_fr');
like($template, qr/\"fr_bye\"\s*=\>\s*\\\"Good bye!\"/, 'fr_bye');
unlike($template, qr/\"thankyou_fr\"/, 'thankyou_fr');

done_testing;
__END__


