#!usr/bin/env perl
use lib '../lib';
use Mojolicious::Lite;
use Test::More;
use Test::Mojo;
use Data::Dumper;

my $t = Test::Mojo->new;
my $app = $t->app;

my $languages = sub  { [qw/pl en de/] };

plugin 'Localize' => {
  dict => {
    welcome => {
      _ => $languages,
      en => 'Welcome!'
    }
  }
};

is(${app->loc->{welcome}->{en}}, 'Welcome!', 'Welcome');

is(ref app->loc->{welcome}->{_}, 'CODE', 'Subroutine');
is(app->loc->{welcome}->{_}->()->[0], 'pl', 'Lang');
is(app->loc->{welcome}->{_}->()->[1], 'en', 'Lang');
is(app->loc->{welcome}->{_}->()->[2], 'de', 'Lang');
ok(!exists app->loc->{welcome}->{de}, 'Kein Willkommen');

plugin Localize => {
  dict => {
    welcome => {
      de => 'Willkommen'
    }
  }
};

is(${ app->loc->{welcome}->{en}}, 'Welcome!', 'Welcome');
is(ref app->loc->{welcome}->{_}, 'CODE', 'Subroutine');
is(${ app->loc->{welcome}->{de}}, 'Willkommen', 'Willkommen');

plugin Localize => {
  dict => {
    welcome_pl => 'Serdecznie witamy, <%= stash "name" %>!'
  }
};

is(${ app->loc->{welcome}->{en}}, 'Welcome!', 'Welcome');
is(${ app->loc->{welcome}->{de}}, 'Willkommen', 'Willkommen');
is(app->loc->{welcome}->{pl}, 'Serdecznie witamy, <%= stash "name" %>!', 'Willkommen (pl1)');

plugin Localize => {
  dict => {
    welcome => {
      de => 'Herzlich Willkommen!'
    }
  }
};

is(${ app->loc->{welcome}->{en} }, 'Welcome!', 'Welcome');
is(${ app->loc->{welcome}->{de} }, 'Willkommen', 'Willkommen');
is(app->loc->{welcome}->{pl}, 'Serdecznie witamy, <%= stash "name" %>!', 'Willkommen (pl2)');

plugin Localize => {
  dict => {
    welcome_de => 'Herzlich Willkommen!'
  },
  override => 1
};

is(${ app->loc->{welcome}->{en}}, 'Welcome!', 'Welcome');
is(${ app->loc->{welcome}->{de}}, 'Herzlich Willkommen!', 'Willkommen');
is(app->loc->{welcome}->{pl}, 'Serdecznie witamy, <%= stash "name" %>!', 'Willkommen (pl3)');

app->defaults(name => 'Peter');
is(app->loc('welcome'), 'Serdecznie witamy, Peter!', 'Polish');
is(app->loc('welcome_de'), 'Herzlich Willkommen!', 'German');
is(app->loc('welcome_en'), 'Welcome!', 'English');

plugin Localize => {
  dict => {
    greeting => {
      '-en' => '<%=loc "welcome" %> Nice to meet you!'
    }
  }
};

app->defaults(name => 'Peter');

is(app->loc('greeting'),
   'Serdecznie witamy, Peter! Nice to meet you!',
 'Combined template');

is(app->loc('welcome_de'), 'Herzlich Willkommen!', 'German');

plugin Localize => {
  dict => {
    greeting => {
      pl => '<%=loc "welcome" %> (polish)',
      _ => $languages
    }
  }
};

app->defaults(name => 'Michael');
is(app->loc('greeting'), 'Serdecznie witamy, Michael! (polish)', 'Polish');

plugin Localize => {
  dict => {
    greeting => {
      de => '<%=loc "welcome_de" %> Schön, dass Du da bist!',
      _ => $languages
    }
  }
};

is(app->loc('greeting_de'), 'Herzlich Willkommen! Schön, dass Du da bist!', 'Deutsch');

plugin Localize => {
  dict => {
    greeting => {
      _ => '<%= "en" %>'
    }
  },
  override => 1
};

is(app->loc('greeting'), 'Serdecznie witamy, Michael! Nice to meet you!',
   'Polish/English');

plugin Localize => {
  dict => {
    greeting => {
      -en => '<%=loc "welcome_en" %> Nice to meet you!'
    }
  },
  override => 1
};

is(app->loc('greeting'), 'Welcome! Nice to meet you!',
   'English');

plugin 'Localize' => {
  dict => {
    greeting => {
      _ => $languages
    }
  },
  override => 1
};

is(app->loc('greeting'), 'Serdecznie witamy, Michael! (polish)',
   'Polish');


# Override preferred key
plugin 'Localize' => {
  dict => {
    greeting => {
      _ => sub  { [qw/xx/] }
    }
  },
  override => 1
};

is(app->loc('greeting'), 'Welcome! Nice to meet you!',
   'English (default)');

# Override default key
plugin 'Localize' => {
  dict => {
    greeting => {
      '-' => 'de'
    }
  },
  override => 1
};

is(app->loc('greeting'), 'Herzlich Willkommen! Schön, dass Du da bist!',
   'German (default)');

# Override default key in short notation
plugin 'Localize' => {
  dict => {
    'greeting_-fr' => 'Bienvenue à! Nous sommes heureux que vous soyez ici!'
  },
  override => 1
};

is(app->loc('greeting'), 'Bienvenue à! Nous sommes heureux que vous soyez ici!',
   'French (default)');

# Override preferred key
plugin 'Localize' => {
  dict => {
    greeting => {
      _ => sub  { [qw/de en fr/] }
    }
  },
  override => 1
};

is(app->loc('greeting'), 'Herzlich Willkommen! Schön, dass Du da bist!',
   'German (preferred)');

# Override preferred key in short notation
plugin 'Localize' => {
  dict => {
    greeting_ => sub  { [qw/en pl fr/] }
  },
  override => 1
};

is(app->loc('greeting'), 'Welcome! Nice to meet you!',
   'English (preferred)');


# Override default key in short notation
plugin Localize => {
  dict => {
    'welcome_-de' => 'Grüß Dich!'
  },
  override => 1
};

is(app->loc('greeting_de'), 'Grüß Dich! Schön, dass Du da bist!',
   'German (direct)');

# Nested defaults
plugin Localize => {
  dict => {
    sorry => {
      -en => {
	-long => q{I'm very sorry!},
	short => q{I'm sorry!}
      },
      de => {
	-long => q{Tut mir sehr leid!},
	short => q{Tut mir leid!}
      }
    }
  }
};

is(app->loc('sorry'), 'I\'m very sorry!',
   'English (default)');
is(app->loc('sorry_short'), 'I\'m sorry!',
   'English (default)');

is(app->loc('sorry_de_short'), 'Tut mir leid!',
   'German short (direct)');
is(app->loc('sorry_de'), 'Tut mir sehr leid!',
   'German short (direct)');

done_testing;
