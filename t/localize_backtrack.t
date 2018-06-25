#!usr/bin/env perl
use lib '../lib';
use Mojolicious::Lite;
use Mojolicious::Plugin::Localize;
use Test::More;
use Test::Mojo;
use Data::Dumper;

my $t = Test::Mojo->new;
my $app = $t->app;

my $languages_ref =  [qw/pl en de/];
my $languages = sub  {
  return $languages_ref
};

$ENV{MOJO_LOCALIZE_DEBUG} = 0;

my $dict = {
  _ => $languages,
  '-' => 'en',
  svs => {
    literature => 'Rongorongo kapikapisigha'
  },
  en => {
    username => 'Username'
  },
  de => {
    username => 'Benutzername'
  },
  Test => {
    _ => $languages,
    '-' => 'en',
    en => {
      pwdconfirm => 'Confirm password'
    },
    de => {
      pwdconfirm => 'Passwort bestätigen'
    }
  }
};

plugin 'Localize' => {
  dict => $dict
};

is($app->loc('username'), 'Username', 'Localization fine');
is($app->loc('Test_pwdconfirm'), 'Confirm password', 'Confirm password');

@$languages_ref =  (qw/de en/);

is($app->loc('username'), 'Benutzername', 'Benutzername');
is($app->loc('Test_pwdconfirm'), 'Passwort bestätigen', 'Passwort bestätigen');

@$languages_ref =  (qw/svs de en/);

is($app->loc('username'), 'Benutzername', 'Username');
is($app->loc('Test_pwdconfirm'), 'Passwort bestätigen', 'Confirm password');

@$languages_ref =  (qw/de en/);

is($app->loc('username'), 'Benutzername', 'Benutzername');
is($app->loc('Test_pwdconfirm'), 'Passwort bestätigen', 'Passwort bestätigen');

@$languages_ref =  (qw/svs en de/);

is($app->loc('username'), 'Username', 'Username');
is($app->loc('Test_pwdconfirm'), 'Confirm password', 'Confirm password');

# Reset dictionary
%{$app->localize->dictionary} = ();

# Always mark default entries
$app->plugin('Localize' => {
  dict => {
      _ => $languages,
      en => {
        title => {
          -short => 'My Sojolicious',
          desc => 'A federated social web toolkit'
        }
      },
      de => {
        title => {
          short => 'Mein Sojolicious',
          desc => 'Ein Werkzeugkasten für das Social Web'
        }
      }
    }
});

@$languages_ref =  (qw/en de/);
is($app->loc('title'), 'My Sojolicious', 'Title');
@$languages_ref =  (qw/de en/);
is($app->loc('title'), 'My Sojolicious', 'Title');



done_testing;
__END__

