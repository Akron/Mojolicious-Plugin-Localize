#!usr/bin/env perl
use Mojolicious::Lite;
use Test::More;
use Test::Mojo;
use Data::Dumper;

my $t = Test::Mojo->new;
my $app = $t->app;

plugin Localize => {
  dict => {
    _ => $languages,
    -en => {
      welcome => 'Welcome'
    },
    de => {
      welcome => 'Willkommen'
    }
  }
};
