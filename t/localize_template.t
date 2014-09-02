#!usr/bin/env perl
use lib '../lib';
use Mojolicious::Lite;
use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new;
my $app = $t->app;
$app->renderer->add_helper(smiley => sub { ';-)' });
my $c = Mojolicious::Controller->new;
$c->app($app);

my $languages = sub  { [qw/pl en de/] };

plugin 'Localize' => {
  dict => {
    welcome => {
      _ => $languages,
      en => 'Welcome',
      de => 'Willkommen'
    }
  }
};

get '/' => sub {
  shift->render(inline => "<%=loc 'welcome' %>");
};

get '/de' => sub {
  shift->render(inline => "<%=loc 'welcome_de' %>");
};

$t->get_ok('/')->status_is(200)->content_is("Welcome\n");
$t->get_ok('/de')->status_is(200)->content_is("Willkommen\n");

my $template = <<'TEMPLATE';
Yeah!
%= loc 'greeting2', begin
%   loc_for 'greeting2_de', begin
<%= loc 'welcome_de' %> Ich hoffe, Du findest Dich hier zurecht, <%= stash 'user' %>! <%= smiley %>
%   end
%   loc_for 'greeting2_-en', begin
<%= loc 'welcome_en' %> I hope, you are fine, <%= stash 'user' %>! <%= smiley %>
%   end
% end
TEMPLATE

get '/user/:user' => sub {
  shift->render(inline => $template);
};

$t->get_ok('/user/Peter')->status_is(200)->content_is("Yeah!\nWelcome I hope, you are fine, Peter! ;-)\n");

$t->get_ok('/user/Michael')->status_is(200)->content_is("Yeah!\nWelcome I hope, you are fine, Michael! ;-)\n");

done_testing;
