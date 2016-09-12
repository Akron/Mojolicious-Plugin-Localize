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

$ENV{MOJO_LOCALIZE_DEBUG} = 0;

use_ok('Mojolicious::Plugin::Localize::Command::localize');
my $dict = Mojolicious::Plugin::Localize::Command::localize->new;
$dict->app($app);

like($dict->usage, qr/usage: perl app\.pl localize/, 'Usage');

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
  qr/localize/,
  'Show generate'
);

stdout_like(
  sub {
    local $ENV{HARNESS_ACTIVE} = 0;
    $cmds->run('localize');
  },
  qr/app\.pl localize/,
  'SYNOPSIS'
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
    $cmds->run('localize', 'en', 'fr');
  }
);

like($template, qr/\"welcome_fr\"\s*=\>\s*\\\"Welcome!\"/, 'welcome_fr');
like($template, qr/\"fr_bye\"\s*=\>\s*\\\"Good bye!\"/, 'fr_bye');
unlike($template, qr/\"thankyou_fr\"/, 'thankyou_fr');

# Reset dictionary
%{$app->localize->dictionary} = ();

# Use synopsis dictionary
$app->plugin('Localize' => {
  dict => {
    _ => sub { $_->locale },
    de => {
      welcome => 'Willkommen!',
      thankyou => 'Danke!'
    },
    fr => {
      thankyou => 'Merci!'
    },
    -en => {
      welcome => 'Welcome!',
      thankyou => 'Thank you!',
    },
    MyPlugin => {
      bye => {
        _ => sub { $_->locale },
        de => 'Auf Wiedersehen!',
        en => 'Good bye!'
      },
      user => {
        _ => sub { $_->locale },
        de => 'Nutzer'
      }
    }
  }
});

# Use en as base
$template = stdout_from(
  sub {
    local $ENV{HARNESS_ACTIVE} = 0;

    # Get a template for french based on the english dictionary
    $cmds->run('localize', 'en', 'fr');
  }
);

like($template, qr/\"fr_welcome\"\s*=\>\s*\\\"Welcome!\"/, 'welcome_fr');
like($template, qr/\"MyPlugin_bye_fr\"\s*=\>\s*\\\"Good bye!\"/, 'fr_bye');
unlike($template, qr/\"fr_thankyou\"/, 'No merci');

# Use en as base
$template = stdout_from(
  sub {
    local $ENV{HARNESS_ACTIVE} = 0;

    # Get a template for french based on the english dictionary
    $cmds->run('localize', 'de', 'fr');
  }
);

like($template, qr/\"fr_welcome\"\s*=\>\s*\\\"Willkommen!\"/, 'welcome_fr');
like($template, qr/\"MyPlugin_bye_fr\"\s*=\>\s*\\\"Auf Wiedersehen!\"/, 'fr_bye');
like($template, qr/\"MyPlugin_user_fr\"\s*=\>\s*\\\"Nutzer\"/, 'fr_bye');
unlike($template, qr/\"fr_thankyou\"/, 'No merci');

# TODO: Check for keys like +_welcome_*_hui


done_testing;
__END__


