package Mojolicious::Plugin::Localize;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/trim/;
use Mojolicious::Plugin::Config;
use File::Spec::Functions 'file_name_is_absolute';
use List::MoreUtils 'uniq';

# $Data::Dumper::Deparse = 1;

# Wrap http://search.cpan.org/~reneeb/Mojolicious-Plugin-I18NUtils-0.05/lib/Mojolicious/Plugin/I18NUtils.pm

# TODO: 'd' is probably better than 'loc'
#       'd' for dictionary lookup
# TODO: use Hash::Merge or Hash::Merge::Small
# TODO: Use Mojo::Template directly
# TODO: deal with:
#       <%=numsep $g_count %> <%=num $g_count, 'guest', 'guests' %> online.'
# TODO: Deal with bidirectional text

use constant DEBUG => $ENV{MOJO_LOCALIZE_DEBUG} || 0;
our $VERSION = '0.11';

# Warning: This only works for default EP templates
our $TEMPLATE_INDICATOR = qr/(?:^\s*\%)|<\%/m;

# Global dictionary hash
our $global = {};

# Register plugin
sub register {
  my ($self, $mojo, $param) = @_;

  # state $global   = {};
  # state $template = {};
  state $init = 0;

  my (@dict, @resources);
  @dict      = ($param->{dict})       if $param->{dict};      # Hashes
  @resources = @{$param->{resources}} if $param->{resources}; # File names

  # Not yet initialized
  unless ($init) {

    # Load parameter from config file
    if (my $c_param = $mojo->config('Localize')) {

      # Prefer the configuration dictionary
      push @dict, $c_param->{dict} if $c_param->{dict};

      # Prefer the configuration override parameter
      $param->{override} = $c_param->{override} if $c_param->{override};

      # Add configuration resources
      if ($c_param->{resources}) {
        unshift @resources, @{$c_param->{resources}};
      };
    };

    # Load default helper
    $mojo->plugin('Localize::Number');
    $mojo->plugin('Localize::Locale');

    # Localization helper
    $mojo->helper(loc2 => \&_localize);

    $mojo->helper(
      loc => sub {
        my $c = shift;

        # Return complete dictionary in case no parameter is defined
        # This is not documented and may change in further versions
        return $global unless scalar @_;

        my $key = [split('_', shift)];

        if (DEBUG) {
          warn '[LOOKUP] Search for "' . join('_',  @$key) . '"' ;
        };

        # If a default entry is given, get it
        my $default_entry = shift if @_ && @_ % 2 != 0;

        # Store all other values in the stash
        my %stash = @_;
        return _lookup($c, \%stash, $global, $key, 0, \%stash) ||
          $default_entry // '';
      }
    );

    # Initialized
    $init = 1;
  };

  # Merge dictionary resources
  if (@resources) {

    # Create config loader
    my $config_loader = Mojolicious::Plugin::Config->new;
    my $home = $mojo->home;

    # Load files
    foreach my $file (uniq @resources) {
      $file = $home->rel_file($file) unless file_name_is_absolute $file;

      if (-e $file) {
        if (my $dict = $config_loader->load($file, undef, $mojo)) {
          unshift @dict, [$dict, $file];
          $mojo->log->debug(qq!Successfully loaded dictionary "$file"!);
          next;
        };
      };
      $mojo->log->warn(qq!Unable to load dictionary file "$file"!);
    };
  };

  # Merge dictionary hashes
  foreach (@dict) {
    my $is_array = ref $_ && ref $_ eq 'ARRAY';
    warn '[MERGE] Start merging' .
      ($is_array ? (' of ' . $_->[1]) : '') if DEBUG;
    $self->_merge($global, $is_array ? $_->[0] : $_, $param->{override});
  };
};


# Unflatten short notation
sub _unflatten {
  my ($key, $dict) = @_;
  my $k = $$key;
  my $g_hash = $dict->{$k};

  # Check for preferred key
  if (substr($k, -1, 1) eq '_') {
    $g_hash = { _  => $g_hash };
    chop $k;
  };

  # Build verbose tree
  $g_hash = { $1 => $g_hash } while $k =~ s/_([^_]+)$//;

  # Set root key
  $$key = $k;
  $dict->{$k} = $g_hash;
};


# Store value as string or code reference
sub _store {
  my $value = $_[0];

  # Is template - store as reference
  return $value if ref $value || $value =~ $TEMPLATE_INDICATOR;
  return \$value;
};


# Merge dictionaries
sub _merge {
  my ($self, $global, $dict, $override) = @_;

  # Iterate over all keys
  foreach my $k (keys %$dict) {

    # warn qq![MERGE] Treat key "$k"! if DEBUG;

    # This is a short notation key
    if (index($k, '_') > 0) {
      warn qq![MERGE] Unflatten "$k"! if DEBUG;
      _unflatten(\$k, $dict);
      # warn "... " . dumper $k if DEBUG;
    }

    # Set preferred key
    elsif ($k eq '_') {

      # If override or not set yet, set the new preferred key
      if ($override || !defined $global->{_}) {
        warn qq![MERGE] Override "_"! if DEBUG;
        $global->{_} = $dict->{_};
      };
      next;
    };

    # This is a default key
    if (index($k, '-') == 0) {
      my $standalone = 0;

      warn qq![MERGE] Set a default key of "$k"! if DEBUG;

      # This is a prefixed default key
      if (length($k) > 1) {
        $k = substr($k, 1);
        $dict->{$k} = delete $dict->{"-$k"};
      }

      # This is a standalone default key
      else {
        $k = $dict->{'-'};
        $standalone = 1;
      };

      # If override or not set yet, set the new default key
      if ($override || !defined $global->{'-'}) {
        warn qq![MERGE] Override default key with "$k"! if DEBUG;
        $global->{'-'} = $k;
      };

      next if $standalone;
    };

    # Insert key - if it not yet exists
    if (!$global->{$k}) {

      # Merge the tree
      if (ref $dict->{$k} eq 'HASH') {
        $self->_merge($global->{$k} = {}, $dict->{$k}, $override);
      }

      # Store the plain value
      else {
        $global->{$k} = _store($dict->{$k});
      };
    }

    # Merge key
    elsif (ref($global->{$k}) eq ref($dict->{$k}) && ref($global->{$k}) eq 'HASH') {
      $self->_merge($global->{$k}, $dict->{$k}, $override);
    }

    # Override global and store the plain value
    elsif ($override) {
      $global->{$k} = _store($dict->{$k});
    };
  };
};


# Lookup dictionary entry recursively
sub _lookup {
  my ($c, $stash, $dict, $key, $level) = @_;

  # Get the current input element to consume
  my @keys;
  if ($key->[$level]) {
    @keys = ($key->[$level]);

    if (DEBUG) {
      warn '[LOOKUP] There is a primary key "' . $key->[$level] . '"';
    };
  }

  # No primary key given
  else {

    # Empty entries are forcing preferred and default keys
    $level++;
  };

  if (DEBUG) {
    warn '[LOOKUP] Check keys: ' . join(',', @keys);
  };

  # Check all possibilities
  my $pos = 0;
  my $lazy = 0;

  # Iterate over all possible keys
  while () {

    # No more keys
    if (!$keys[$pos]) {

      warn '[LOOKUP] No more keys - check lazily' if DEBUG;

      # Stop processing
      return if $lazy;

      # Lazy load further keys
      # Add preferred keys
      if ($dict->{'_'}) {
        my @matches = _get_pref_keys($c, $dict->{'_'}, $stash);
        if (DEBUG) {
          warn '[LOOKUP] There are preferred keys "' . join(',', @matches) . '"';
        };
        push @keys, @matches;
      };

      # Add default key
      if ($dict->{'-'}) {
        my $match = $dict->{'-'};
        if (DEBUG) {
          warn '[LOOKUP] There is a default key "' . $match . '"';
        };
        push @keys, $match if $match;
      };

      return unless $keys[$pos];

      warn '[LOOKUP] Check non-manual keys ' . join(',', @keys) if DEBUG;

      # There may be items set multiple times
      @keys = uniq @keys;
      $lazy = 1;
    };

    # Key has a match
    if (my $match = $dict->{$keys[$pos]}) {

      # Debug information
      if (DEBUG) {
        warn '[LOOKUP] Found entry for "' . $keys[$pos] . qq!" on level [$level]!;
      };

      # The match is final
      if (!ref($match) || ref($match) eq 'SCALAR' || ref($match) eq 'CODE') {

        # Everything is cosumed - fine
        if ($level >= $#{$key}) {

          # Value is scalar
          if (ref $match eq 'SCALAR') {
            warn '[LOOKUP] Found scalar value as "' . $$match . '"' if DEBUG;
            return $$match;
          }

          elsif (ref $match eq 'CODE') {
            my $value = $match->($c, %$stash);
            warn qq![LOOKUP] Found subroutine value as "$value"! if DEBUG;
            return $value;
          };

          my $value = $c->include(inline => $match, %$stash);
          $value = trim $value unless delete $stash->{no_trim};
          warn qq![LOOKUP] Found template value as "$value"! if DEBUG;

          return $value;
        };

        # Check another path
      }

      # No final match found - go on
      else {

        my $found = _lookup(
          $c,
          $stash,
          $match,
          $key,

          # The primary word was consumed
          $pos ? $level : $level + 1
        );

        # Found something
        return $found if $found;
      };
    };

    $pos++;
  };
};


# Return preferred keys
sub _get_pref_keys {
  my ($c, $index, $stash) = @_;

  return unless $index;

  # Preferred key is a template
  unless (ref $index) {

    my $key = $c->include(inline => $index, %$stash);
    $key = trim $key unless delete $stash->{no_trim};

    if (DEBUG) {
      warn qq![LOOKUP] Found preferred template key "$index" to "$key"!;
    };

    return $key;
  }

  # Preferred key is a subroutine
  elsif (ref $index eq 'CODE') {

    local $_ = $c->localize;
    my $pref = $index->($c);

    if (DEBUG) {
      warn qq![LOOKUP] Check preferred code key ! . join(',', @$pref);
    };

    return ref $pref ? @$pref : ($pref);
  }

  # Preferred key is an array
  elsif (ref $index eq 'ARRAY') {
    if (DEBUG) {
      warn qq![LOOKUP] Check preferred array key "$_"!;
    };

    return @{$index};
  };

  # No preferred keys or invalid notation
  return;
};


1;


__END__

=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Localize - Localization Framework for Mojolicious


=head1 SYNOPSIS

  # Register the plugin with a defined dictionary
  plugin  Localize => {
    dict => {
      _  => sub { $_->locale },
      de => {
        welcome => "Willkommen in <%=loc 'App_name_land' %>!",
        bye => 'Auf Wiedersehen!'
      },
      -en => {
        welcome => "Welcome to <%=loc 'App_name_land' %>!",
        bye => 'Good bye!'
      },
      App => {
        name => {
          -long => 'Mojolicious',
          short => 'Mojo',
          land  => 'MojoLand'
        }
      }
    }
  };

  # Call dictionary entries from templates
  %= loc 'welcome'

  # If the user has a preferred locale of 'en',
  # the output is 'Welcome to MojoLand!'


=head1 DESCRIPTION

L<Mojolicious::Plugin::Localize> is a localization framework for
Mojolicious, heavily inspired by Mozilla's L<l20n|http://l20n.org/>.
Instead of being a reimplementation it uses L<Mojo::Template> for string interpolation,
L<Mojolicious::Plugin::Config> for dictionaries and L<helpers|Mojolicious/helper>
for template functions.

B<Warning!> This is early software and behaviour may change without notifications!


=head1 METHODS

L<Mojolicious::Plugin::Localize> inherits all methods
from L<Mojolicious::Plugin> and implements the following
new ones.

=head2 register

  app->plugin(Localize => {
    dict => {
      _  => sub { $_->locale },
      de => {
        welcome => 'Willkommen!',
        bye => 'Auf Wiedersehen!',
      },
      en => {
        welcome => 'Welcome!',
        bye => 'Good bye!'
      }
    },
    override  => 1,
    resources => ['french.dict', 'polish.dict']
  });

Called when registering the plugin.

Expects a parameter C<dict> containing a localization L<dictionary|/DICTIONARIES>.
Further dictionary files to be loaded can be passed as an array reference
using the C<resources> parameter.

The plugin can be registered multiple times, and defined dictionaries will be merged.

Already existing key definitions won't be overridden in that way
unless an additional C<override> parameter is set to a C<true> value.
Dictionary entries from resource files, on the other hand, will always override,
so the order of the given array is of relevance.

All parameters can be set either on registration or in a configuration file
with the key C<Localize> (loaded only on first registration).


=head1 HELPERS

In addition to the listed helpers,
L<Mojolicious::Plugin::Localize> loads further helpers by default,
see L<num|Mojolicious::Plugin::Localize::Number> and
L<localize.locale|Mojolicious::Plugin::Localize::Locale>.


=head2 loc

  # Lookup a dictionary entry as a controller method
  my $entry = $c->loc('welcome');

  %# Lookup a dictionary entry in templates
  <%= loc 'welcome' %>
  <%= loc 'welcome', 'Welcome to the site!' %>
  <%= loc 'welcome', user => 'Peter' %>
  <%= loc 'welcome', 'Welcome to the site!', user => 'Peter' %>

Makes a dictionary lookup and returns a string.

Expects a dictionary key, an optional fallback message and optional stash values.


=head2 localize

  $c->localize->locale('de');

Helper object for nested helpers.
L<Mojolicious::Plugin::Localize> loads further plugins establishing nested helpers,
see L<localize.locale|Mojolicious::Plugin::Localize::Locale>.


=head1 DICTIONARIES

Dictionaries can be loaded by registering the plugin either as a passed C<dict> value
or in separated files using the C<resources> parameter.

=head2 Notation

  {
    en => {
      tree => {
        sg => 'Tree',
        pl => 'Trees'
    },
    de => {
      tree => {
        sg => 'Baum',
        pl => 'Bäume'
      }
    }
  }

Dictionaries are nested hash references.
On each level, there is a key that can either lead to a subdictionary
or to a value.

  {
    en => {
      welcome => 'Welcome!'
      greeting => '<%= loc "en_welcome" %> Nice to meet you, <%= $user %>!'
    },
    de => {
      welcome => 'Willkommen!',
      greeting => '<%= loc "de_welcome" %> Schön, Dich zu sehen, <%= $user %>!'
    }
  }

Values may be strings, L<Mojo::Template> strings (with default configuration),
or code references (with the controller object passed when evaluating,
followed by further parameters as a hash).

As you see above, values may fetch further dictionary entries using the L<loc|/loc> helper.
To fetch entries from the dictionary using the L<loc|/loc> helper,
the user has to pass the key structure in so-called I<short notation>, by adding
underscores following they key's path.
The short notation for the entry C<Bäume> in the first example is C<de_tree_pl>.

  %= loc 'de_tree_pl'
  %# 'Bäume'

The short notation can also be used to add new dictionary entries
using dictionary files or the C<dict> parameter of the plugins registration handler.
The following dictionary definitions are therefore equal:

  {
    de => {
      welcome => 'Willkommen!'
    }
  }

  {
    de_welcome => 'Willkommen!'
  }

There is no limitation for nesting or the order of dictionary entries.

Keys need to contain alphanumeric characters only,
as special characters are reserved for later use.


=head2 Preferred Keys

The underscore is a special key, marking preferred keys on the dictionary level,
in case no matching key can be found on that level
(which is the case when a key in short notation is underspecified).

  {
    welcome => {
      _ => 'en',
      de => 'Willkommen!'
      en => 'Welcome!'
    }
  }

In case the key C<welcome_de> is requested with the above dictionary established,
the value C<Willkommen!> will be returned.
But if the underspecified key C<welcome> is requested without a matching key on the
final level, the preferred key C<en> will
be used instead, returning the value C<Welcome!>.

Preferred keys can exist on any level of the nesting and are always called when
there is no matching key as part of the short notation.

Preferred keys may contain the key as a string, a L<Mojo::Template>, an array reference
of keys (in order of preference), or a subroutine returning either a string or an array
reference.

  # The preferred key is 'en'
  _ => 'en'

  # The preferred key is the stash value of 'user_status' (e.g. 'mod' or 'admin')
  _ => '<%= $user_status %>'
  _ => sub { shift->stash('user_status') }

  # The preferred key is 'en', and in case this isn't defined, it's 'de' etc.
  _ => [qw/en de/]
  _ => sub { [qw/en de/] }

The first parameter passed to subroutines is the controller object,
and the local variable C<$_> is set to the L<nested helper object|/localize>,
which eases calls to, for example,
the L<localize.locale|Mojolicious::Plugin::Localize::locale> helper

  # The preferred key is based on the user agent's localization
  _ => sub { $_->locale }

Preferred keys in I<short notation> have a trailing underscore:

  # Set the preferred key in nested notation:
  {
    greeting => {
      _ => sub { $_->locale },
      en => 'Hello!',
      de => 'Hallo!'
    }
  }

  # Set the preferred key in short notation:
  {
    greeting_ => sub { $_->locale }
    greeting_en => 'Hello!',
    greeting_de => 'Hallo!'
  }


=head2 Default Keys

The dash symbol is a special key, marking default keys on the dictionary level,
in case no matching or preferred key can be found on that level.
They can be given in addition to preferred keys.

  {
    welcome => {
      _   => 'pl',
      '-' => 'en',
      en  => 'Welcome!',
      de  => 'Welcome!'
    }
  }

In case the key C<welcome_de> is requested with the above dictionary
established, the value C<Willkommen!> will be returned.
But if the underspecified key C<welcome> is requested without a
matching key on the final level, and the preferred key C<pl>
isn't defined in another dictionary, the default key C<en> will
be used instead, returning the value C<Welcome!>.

Default keys can be alternatively marked with a leading dash symbol.

  {
    welcome => {
      _   => 'pl',
      -en => 'Welcome!',
      de  => 'Welcome!'
    }
  }

To define default keys in I<short notation>, prepend a dash to each subkey in question.

  {
    'welcome_-en' => 'Welcome!',
    'welcome_de'  => 'Willkomen!'
  }


=head2 Forcing Preferred and Default Keys

  {
    Lang => {
      _ => [qw/en de pl/],
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

In rare occasions a L<loc|/loc> call in short notation has to force the
usage of preferred or default keys over primary key access.
For example, in the above dictionary a call to C<Lang_de>,
expecting the value C<German>, will fail, as the C<de> will
be consumed on the second level and will therefore be missing on the third level.
To force the usage of the preferred or default keys on the second level,
simply prepend another underscore to the second key and call
C<Lang__de> with the expected result.


=head2 Hints and Conventions

L<Mojolicious::Plugin::Localize> let you decide, how to nest
your dictionary entries. For internationalization purposes,
it is a good idea to have the language key on the first
level, so you can establish further entries relying on that
structure (see, e.g., the example snippet in L<SYNOPSIS>).

Instead of passing default messages using the L<loc|/loc> helper,
you should always define default dictionary entries.

Dictionary keys should always be lower case, and plugins,
that provide their own dictionaries, should prefix their keys
with a namespace (e.g. the plugin's name) in camel case,
to prevent clashes with other dictionary entries.
For example the C<welcome> message for this plugin should
be named C<Localize_welcome>.

Template files can be registered as dictionary keys to be
looked up for rendering.

  # Create dictionary keys for templates
  {
    Template => {
      _ => sub { $_->locale },
      -en => {
        start => 'en/start'
      },
      de => {
        start => 'de/start'
      }
    }
  }

  # Lookup dictionary entry for rendering
  $c->render($c->loc('Template_start'), variant => 'mobile');


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Localize


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014-2016, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
