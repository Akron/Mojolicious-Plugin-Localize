#!usr/bin/env perl
use lib '../lib';
use Mojolicious::Lite;
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

plugin 'Localize' => {
  dict => {
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
  }
};

warn "---------------------------";

#is($app->loc('username'), 'Username', 'Username');
#is($app->loc('Test_pwdconfirm'), 'Confirm password', 'Confirm password');

#@$languages_ref =  (qw/de en/);

#is($app->loc('username'), 'Benutzername', 'Benutzername');
#is($app->loc('Test_pwdconfirm'), 'Passwort bestätigen', 'Passwort bestätigen');

@$languages_ref =  (qw/svs de en/);

is($app->loc('username'), 'Benutzername', 'Benutzername');

done_testing;
__END__

is($app->loc('Test_pwdconfirm'), 'Passwort bestätigen', 'Passwort bestätigen');

@$languages_ref =  (qw/svs en de/);

is($app->loc('username'), 'Username', 'Username');

is($app->loc('MojoOroAccount_pwdconfirm'), 'Confirm password', 'Confirm password');

done_testing;
