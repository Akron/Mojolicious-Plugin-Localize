#!usr/bin/env perl
use lib '../lib';
use Mojolicious::Lite;
use Test::More;
use Test::Mojo;
use Data::Dumper;

my $t = Test::Mojo->new;
my $app = $t->app;

my $languages = sub  { [qw/pl en de/] };

plugin Localize => {
  dict => {
    Lang => {
      _ => $languages,
      -en => {
	de => 'German',
	en => 'English'
      },
      de => {
	de => 'Deutsch',
	en => 'Englisch'
      }
    }
  }
};

is(app->loc('Lang__de'), 'German', 'Force preferred or default key');
is(app->loc('Lang__en'), 'English', 'Force preferred or default key');

done_testing;
